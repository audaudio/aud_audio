// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';

import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  const config = AudLoadGovernorConfig();
  const period = Duration(milliseconds: 100);

  Duration at(int periods) => period * periods;

  /// A period of [units] in use with a window whose mean is [mean].
  AudLoadSample sample(
    int periods, {
    int units = 0,
    double mean = 0.8,
    double? periodMean,
    int xruns = 0,
    int stolen = 0,
  }) => AudLoadSample(
    time: at(periods),
    periodMean: periodMean ?? 0,
    windowMean: mean,
    meanUnits: units.toDouble(),
    units: units,
    xruns: xruns,
    stolen: stolen,
  );

  /// Teaches [policy] the line share = 0.3 + 0.01 x units: a fit of 45.
  void teach(AudLoadPolicy policy) {
    var i = 0;
    for (final units in [10, 30, 50, 20, 40]) {
      policy.step(sample(++i, units: units, periodMean: 0.3 + 0.01 * units));
    }
  }

  group('AudLoadSample', () {
    test('goes to JSON and back', () {
      const s = AudLoadSample(
        time: Duration(milliseconds: 300),
        periodMean: 0.25,
        windowMean: 0.3,
        p99: 0.45,
        max: 0.6,
        meanUnits: 12.5,
        units: 13,
        xruns: 1,
        overloads: 2,
        stolen: 3,
      );
      final back = AudLoadSample.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(s.toString(), contains('meanUnits: 12.5'));
    });

    test('takes missing values of JSON as zero', () {
      final s = AudLoadSample.fromJson(const {'timeMs': 5});
      expect(s.time, const Duration(milliseconds: 5));
      expect(s.p99, 0);
      expect(s.units, 0);
    });
  });

  group('AudLoadPolicy', () {
    group('starts', () {
      test('at the ceiling without a start', () {
        expect(AudLoadPolicy().budget, config.ceiling);
      });

      test('at the start, clamped to the floor and the ceiling', () {
        expect(AudLoadPolicy(start: 40).budget, 40);
        expect(AudLoadPolicy(start: 2).budget, config.floor);
        expect(AudLoadPolicy(start: 999).budget, config.ceiling);
      });

      test('without a cost, a fit, a base or a lowering', () {
        final policy = AudLoadPolicy(start: 40);
        expect(policy.unitCost, isNull);
        expect(policy.fit, isNull);
        expect(policy.baseShare, 0);
        expect(policy.lastDown, isNull);
        expect(policy.settledAfter, Duration.zero);
        expect(policy.config.target, 0.75);
      });
    });

    group('holds', () {
      test('within the band', () {
        final policy = AudLoadPolicy(start: 40);
        expect(policy.step(sample(1, units: 39)), AudLoadAction.hold);
        expect(policy.budget, 40);
      });

      test('below the band when the budget does not limit', () {
        final policy = AudLoadPolicy(start: 40);
        final s = sample(1, units: 10, mean: 0.2);
        expect(policy.step(s), AudLoadAction.hold);
      });

      test('at the ceiling', () {
        final policy = AudLoadPolicy(start: config.ceiling);
        final s = sample(1, units: config.ceiling, mean: 0.2);
        expect(policy.step(s), AudLoadAction.hold);
      });

      test('at the floor, without counting it as a lowering', () {
        final policy = AudLoadPolicy(start: config.floor);
        expect(policy.step(sample(0, xruns: 1)), AudLoadAction.hold);
        expect(policy.budget, config.floor);
        expect(policy.lastDown, isNull);
      });
    });

    group('lowers at once', () {
      test('on an xrun to three quarters of the units in use', () {
        final policy = AudLoadPolicy(start: 100);
        final s = AudLoadSample(
          time: at(3),
          meanUnits: 60,
          units: 80,
          xruns: 1,
        );
        expect(policy.step(s), AudLoadAction.down);
        expect(policy.budget, 60);
        expect(policy.lastDown, at(3));
      });

      test('on an xrun by a step when few units are in use', () {
        final policy = AudLoadPolicy(start: 100);
        policy.step(sample(1, units: 2, xruns: 1));
        expect(policy.budget, 99);
      });

      test('on a mean above the band to the units of the target', () {
        final policy = AudLoadPolicy(start: 100);
        policy.step(sample(1, units: 80, mean: 0.9));
        // 80 x 0.75 / 0.9.
        expect(policy.budget, 66);
      });

      test('on a mean above the band by a step and to the fit', () {
        final policy = AudLoadPolicy(start: 100);
        teach(policy);
        expect(policy.fit, 45);
        // 60 x 0.75 / 0.9 = 50 is less deep than the fit: the fit.
        policy.step(sample(30, units: 60, mean: 0.9));
        expect(policy.budget, 50);
        // At the fit the mean is still too high: the fit is too high.
        policy.step(sample(50, units: 46, mean: 0.88));
        expect(policy.budget, 45);
        policy.step(sample(70, units: 41, mean: 0.88));
        expect(policy.budget, 44);
      });

      test('no deeper than the units scaled to the target', () {
        final policy = AudLoadPolicy(start: 100);
        // A line that puts the fit at the floor.
        var i = 0;
        for (final units in [10, 30, 50]) {
          policy.step(sample(++i, units: units, periodMean: 0.7 + units / 100));
        }
        expect(policy.fit, config.floor);
        policy.step(sample(30, units: 40, mean: 0.9));
        // 40 x 0.75 / 0.9.
        expect(policy.budget, 33);
      });

      test('on an xrun to three quarters of the units, not to the fit', () {
        final policy = AudLoadPolicy(start: 100);
        teach(policy);
        policy.step(sample(30, units: 80, xruns: 1));
        expect(policy.budget, 60);
        policy.step(sample(31, units: 40, xruns: 1));
        expect(policy.budget, 30);
      });

      test('counts the mean again only once the window has passed', () {
        final policy = AudLoadPolicy(start: 100);
        policy.step(sample(1, units: 80, mean: 0.9));
        expect(policy.budget, 66);
        // The window still holds renders from before.
        expect(
          policy.step(sample(5, units: 58, mean: 0.9)),
          AudLoadAction.hold,
        );
        // An xrun counts at once.
        expect(policy.step(sample(6, units: 40, xruns: 1)), AudLoadAction.down);
        expect(policy.budget, 30);
        // After the window the mean counts again.
        final s = sample(16, units: 26, mean: 0.91);
        expect(policy.step(s), AudLoadAction.down);
        expect(policy.budget, 21);
      });
    });

    group('raises slowly', () {
      test('by a step while below the band and limiting', () {
        final policy = AudLoadPolicy(start: 40);
        final s = sample(1, units: 36, mean: 0.5);
        expect(policy.step(s, reserve: 4), AudLoadAction.up);
        expect(policy.budget, 41);
      });

      test('when the owner stole units', () {
        final policy = AudLoadPolicy(start: 40);
        final s = sample(1, units: 20, mean: 0.5, stolen: 3);
        expect(policy.step(s), AudLoadAction.up);
      });

      test('not within the hold after a lowering', () {
        final policy = AudLoadPolicy(start: 40);
        policy.step(sample(1, units: 2, xruns: 1));
        expect(policy.budget, 39);
        final early = sample(10, units: 39, mean: 0.5);
        expect(policy.step(early), AudLoadAction.hold);
        final late = sample(21, units: 39, mean: 0.5);
        expect(policy.step(late), AudLoadAction.up);
      });

      test('beyond the fit while the mean stays low', () {
        final policy = AudLoadPolicy(start: 45);
        teach(policy);
        final s = sample(10, units: 45, mean: 0.5);
        expect(policy.step(s), AudLoadAction.up);
        expect(policy.budget, 46);
      });
    });

    group('learns', () {
      test('the line of the mean share over the units in use', () {
        final policy = AudLoadPolicy(start: 40);
        teach(policy);
        expect(policy.unitCost, closeTo(0.01, 1e-9));
        expect(policy.baseShare, closeTo(0.3, 1e-9));
        expect(policy.fit, 45);
      });

      test('no line while the units in use hardly change', () {
        final policy = AudLoadPolicy(start: 40);
        for (var i = 1; i < 20; i++) {
          policy.step(sample(i, units: 20 + i % 2, periodMean: 0.5));
        }
        expect(policy.unitCost, isNull);
      });

      test('nothing from periods without units or load', () {
        final policy = AudLoadPolicy(start: 40);
        policy.step(sample(1, units: 0, periodMean: 0.2));
        policy.step(sample(2, units: 30));
        policy.step(sample(3, units: 10, periodMean: 0.4));
        expect(policy.unitCost, isNull);
      });

      test('the new line once the old one is forgotten', () {
        final policy = AudLoadPolicy(start: 40);
        teach(policy);
        // Now share = 0.2 + 0.02 x units.
        for (var i = 10; i < 600; i++) {
          final units = 10 + i % 30;
          policy.step(sample(i, units: units, periodMean: 0.2 + 0.02 * units));
        }
        expect(policy.unitCost, closeTo(0.02, 1e-4));
        expect(policy.baseShare, closeTo(0.2, 1e-3));
      });

      test('no fit from a cost of zero', () {
        final policy = AudLoadPolicy(start: 40);
        var i = 0;
        for (final units in [10, 30, 50]) {
          policy.step(sample(++i, units: units, periodMean: 0.9 - units / 100));
        }
        expect(policy.unitCost, 0);
        expect(policy.fit, isNull);
      });

      test('again after the timing changed; the budget stays', () {
        final policy = AudLoadPolicy(start: 40);
        teach(policy);
        policy.timingChanged();
        expect(policy.unitCost, isNull);
        expect(policy.baseShare, 0);
        expect(policy.budget, 40);
        policy.step(sample(10, units: 20, periodMean: 0.5));
        expect(policy.unitCost, isNull);
      });
    });

    group('settles', () {
      test('when the budget has not fallen for the settle time', () {
        final policy = AudLoadPolicy(start: 40);
        expect(policy.settled(at(99)), isFalse);
        expect(policy.settled(at(100)), isTrue);
        policy.step(sample(120, units: 30, xruns: 1));
        expect(policy.settled(at(219)), isFalse);
        expect(policy.settled(at(220)), isTrue);
        expect(policy.settledAfter, at(120));
      });
    });

    group('in a simulation of the stress test', () {
      for (final device in _devices) {
        for (final start in [config.floor, 64, config.ceiling]) {
          test('settles on ${device.name} from $start without xruns after', () {
            final run = _simulate(device: device, start: start);
            expect(
              run.settledAfter,
              lessThan(const Duration(seconds: 30)),
              reason: run.toString(),
            );
            expect(run.xrunsAfterSettling, 0, reason: run.toString());
            // Not far above the units that keep the mean at the target -
            // a start above them stays while the player never asks for
            // that many -, and close to them or to what the player asks
            // for.
            expect(
              run.budget,
              lessThanOrEqualTo(max(device.fit * 1.25, start)),
              reason: run.toString(),
            );
            expect(
              run.budget,
              greaterThanOrEqualTo(min(device.fit, run.peakDemand) * 0.6),
              reason: run.toString(),
            );
          });
        }
      }

      test('rides out xruns that come without load', () {
        final device = _devices.first;
        final run = _simulate(
          device: device,
          start: 64,
          spuriousXrunEvery: 300,
        );
        expect(
          run.budget,
          greaterThanOrEqualTo(device.fit * 0.5),
          reason: run.toString(),
        );
      });
    });
  });
}

// .............................................................................
/// A modeled device: the mean share of the block is [base] plus [cost] per
/// voice, and the stream drops out above [xrunAt]. The first is the
/// Galaxy Tab S4 of the sweep of ticket 29.
typedef _Device = ({String name, double base, double cost, double xrunAt});

const List<_Device> _devices = [
  (name: 'the Galaxy Tab S4', base: 0.37, cost: 0.008, xrunAt: 0.88),
  (name: 'a phone', base: 0.1, cost: 0.004, xrunAt: 0.9),
  (name: 'a fast tablet', base: 0.05, cost: 0.0015, xrunAt: 0.9),
];

extension on _Device {
  /// The voices that keep the mean at the target of 75 %, at most 256.
  double get fit => min(256, (0.75 - base) / cost);
}

typedef _Run = ({
  int budget,
  int peakDemand,
  Duration settledAfter,
  int xrunsAfterSettling,
});

/// Plays the stress test of ticket 28 on [device] for 60 s - every 250 ms a
/// bass note, a chord of 6 to 8 notes and a melody note at the next step's
/// note offs, the sustain pedal down for 2 s of every 4 s, each note with
/// two layers that ring 1.5 s after their release - and lets an
/// [AudLoadPolicy] set the budget every 100 ms; the sampler keeps a reserve
/// of 4 voices and steals released voices first, then the oldest.
_Run _simulate({
  required _Device device,
  required int start,
  int spuriousXrunEvery = 0,
}) {
  const reserve = 4;
  const period = Duration(milliseconds: 100);
  final random = Random(29);
  final policy = AudLoadPolicy(start: start);
  // The voices: the tick they started and the tick they were released.
  final voices = <({int born, int? released})>[];
  final means = <double>[];
  final xruns = <Duration>[];
  var peakDemand = 0;
  for (var tick = 1; tick <= 600; tick++) {
    final time = period * tick;
    // The player, every 250 ms: note offs for the last notes, new notes.
    if (tick * 100 % 250 < 100) {
      final step = tick * 100 ~/ 250;
      final pedal = step % 16 >= 8;
      if (!pedal) {
        for (var i = 0; i < voices.length; i++) {
          final v = voices[i];
          if (v.released == null) voices[i] = (born: v.born, released: tick);
        }
      }
      final notes = 1 + 6 + step % 3 + 1;
      for (var i = 0; i < notes * 2; i++) {
        voices.add((born: tick, released: null));
      }
    }
    voices.removeWhere((v) => v.released != null && tick - v.released! > 15);
    peakDemand = max(peakDemand, voices.length);
    // The sampler keeps the reserve: released voices first, the oldest.
    final limit = max(1, policy.budget - reserve);
    final steal = max(0, voices.length - limit);
    if (steal > 0) {
      voices.sort((a, b) {
        if ((a.released != null) != (b.released != null)) {
          return a.released != null ? -1 : 1;
        }
        return a.born.compareTo(b.born);
      });
      voices.removeRange(0, steal);
    }
    // The device.
    final units = voices.length.toDouble();
    final noise = 1 + (random.nextDouble() - 0.5) * 0.04;
    final mean = (device.base + device.cost * units) * noise;
    means.add(mean);
    if (means.length > 10) means.removeAt(0);
    final windowMean = means.reduce((a, b) => a + b) / means.length;
    var xrun = mean > device.xrunAt ? 1 : 0;
    if (spuriousXrunEvery > 0 && tick % spuriousXrunEvery == 0) xrun = 1;
    if (xrun > 0) xruns.add(time);
    policy.step(
      AudLoadSample(
        time: time,
        periodMean: mean,
        windowMean: windowMean,
        meanUnits: units,
        units: voices.length,
        xruns: xrun,
        stolen: steal,
      ),
      reserve: reserve,
    );
  }
  final settledAfter = policy.settledAfter;
  return (
    budget: policy.budget,
    peakDemand: peakDemand,
    settledAfter: settledAfter,
    xrunsAfterSettling: xruns.where((t) => t > settledAfter).length,
  );
}
