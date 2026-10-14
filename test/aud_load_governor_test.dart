// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('AudLoadGovernor', () {
    late AudEngineFfi engine;
    late _Budget budget;
    late Duration now;
    late List<_Timer> timers;
    late AudLoadGovernor governor;

    AudLoadGovernor create({int? start = 40}) => AudLoadGovernor(
      budget: budget,
      start: start,
      periodic: (period, tick) {
        final timer = _Timer(period, tick);
        timers.add(timer);
        return timer;
      },
      clock: () => now,
    );

    /// Renders [frames] on the manual clock of the null device.
    void play(int frames) {
      var host = AudClock.nowNs();
      for (var done = 0; done < frames; done += 480) {
        engine.stream.debugProcess(frames: 480, hostTimeNs: host);
        host += (480 * 1e9 / engine.format.sampleRate).round();
      }
    }

    /// Lets [time] pass and the timer fire.
    void pass(Duration time) {
      now += time;
      timers.last.fire();
    }

    setUp(() {
      engine = AudEngineFfi(
        config: const AudEngineConfig(
          backend: AudIoBackend.nullDevice,
          outputChannels: 1,
          maxFrames: 256,
          manualClock: true,
        ),
      );
      addTearDown(engine.dispose);
      budget = _Budget();
      now = Duration.zero;
      timers = [];
      governor = create();
      engine.addExtension(governor);
    });

    test('has a name, the policy and an empty state before it starts', () {
      expect(governor.name, 'load governor of test voices');
      expect(governor.policy.budget, 40);
      expect(governor.config.period, const Duration(milliseconds: 100));
      expect(governor.state.budget, 0);
      expect(governor.lastSample.time, Duration.zero);
      expect(governor.isRunning, isFalse);
    });

    test('sets the start budget and ticks every period while running', () {
      engine.start();
      expect(budget.limit, 40);
      expect(governor.isRunning, isTrue);
      expect(timers.single.period, const Duration(milliseconds: 100));
      final states = <AudLoadGovernorState>[];
      governor.states.listen(states.add);
      play(4800);
      budget.usage = const AudLoadBudgetUsage(units: 10, unitFrames: 48000);
      pass(const Duration(milliseconds: 100));
      expect(states, hasLength(1));
      final state = governor.state;
      expect(state.time, const Duration(milliseconds: 100));
      expect(state.budget, 40);
      expect(state.units, 10);
      // 48000 unit frames in 100 ms at 48 kHz: ten units.
      expect(
        state.meanUnits,
        closeTo(48000 / engine.format.sampleRate / 0.1, 1e-6),
      );
      expect(state.load.renders, greaterThan(0));
      expect(state.load.p99, lessThan(0.4));
      expect(state.action, AudLoadAction.hold);
      expect(state.xruns, 0);
      expect(state.settled, isFalse);
      expect(governor.lastSample.units, 10);
      expect(governor.lastSample.periodMean, state.periodMean);
    });

    test('raises the budget while the load is low and the budget limits', () {
      engine.start();
      play(4800);
      budget.usage = const AudLoadBudgetUsage(units: 36, unitFrames: 172800);
      pass(const Duration(milliseconds: 100));
      expect(governor.state.action, AudLoadAction.up);
      expect(budget.limit, 41);
      expect(governor.state.budget, 41);
    });

    test('counts the stolen units per minute', () {
      engine.start();
      for (var i = 1; i <= 20; i++) {
        play(480);
        budget.usage = AudLoadBudgetUsage(units: 1, stolen: i * 3);
        pass(const Duration(milliseconds: 100));
      }
      // 57 stolen in the 1.9 s since the first period.
      expect(governor.state.stolen, 60);
      expect(governor.state.stolenPerMinute, closeTo(57 / 1.9 * 60, 1e-6));
      // Older periods leave the minute.
      for (var i = 0; i < 700; i++) {
        pass(const Duration(milliseconds: 100));
      }
      expect(governor.state.stolenPerMinute, 0);
    });

    test('settles when the budget has not fallen for the settle time', () {
      engine.start();
      for (var i = 0; i < 100; i++) {
        pass(const Duration(milliseconds: 100));
      }
      expect(governor.state.settled, isTrue);
      expect(governor.state.settledAfter, Duration.zero);
    });

    test('stops looking when the engine stops and goes on at a start', () {
      engine.start();
      engine.stop();
      expect(governor.isRunning, isFalse);
      expect(timers.single.isActive, isFalse);
      // A late tick of a stopped engine does nothing.
      now += const Duration(milliseconds: 100);
      governor.tick();
      expect(governor.state.time, Duration.zero);
      engine.start();
      expect(governor.isRunning, isTrue);
      expect(timers, hasLength(2));
      pass(const Duration(milliseconds: 100));
      expect(governor.state.time, const Duration(milliseconds: 200));
    });

    test('starts its counters again after a pause', () {
      engine.start();
      pass(const Duration(milliseconds: 100));
      expect(governor.state.time, const Duration(milliseconds: 100));
      // A second without a look - a suspended engine, a busy isolate.
      budget.usage = const AudLoadBudgetUsage(units: 40, stolen: 500);
      pass(const Duration(seconds: 1));
      expect(governor.state.time, const Duration(milliseconds: 100));
      pass(const Duration(milliseconds: 100));
      expect(governor.state.time, const Duration(milliseconds: 1200));
      // The stolen units of the pause do not count.
      expect(governor.state.stolen, 0);
    });

    test('skips a tick without time', () {
      engine.start();
      timers.last.fire();
      expect(governor.state.time, Duration.zero);
    });

    test('forgets the cost of a unit when the timing changes', () {
      engine.start();
      // Three periods of 10, 30 and 50 units: the policy fits its line.
      var unitFrames = 0;
      for (final units in [10, 30, 50]) {
        play(4800);
        unitFrames += units * 4800;
        budget.usage = AudLoadBudgetUsage(units: units, unitFrames: unitFrames);
        pass(const Duration(milliseconds: 100));
      }
      expect(governor.policy.unitCost, isNotNull);
      final limit = budget.limit;
      governor.engineTimingChanged(engine);
      expect(governor.policy.unitCost, isNull);
      expect(budget.limit, limit);
      expect(governor.policy.budget, limit);
    });

    test('closes its states when the engine goes', () async {
      engine.start();
      final done = governor.states.toList();
      engine.dispose();
      expect(await done, isEmpty);
      expect(governor.isRunning, isFalse);
      expect(timers.single.isActive, isFalse);
    });

    test('starts from the ceiling without a start and uses a real timer', () {
      final other = AudLoadGovernor(budget: _Budget());
      expect(other.policy.budget, other.config.ceiling);
      final engine2 = AudEngineFfi(
        config: const AudEngineConfig(
          backend: AudIoBackend.nullDevice,
          outputChannels: 1,
          maxFrames: 256,
          manualClock: true,
        ),
      );
      engine2.addExtension(other);
      engine2.start();
      expect(other.isRunning, isTrue);
      other.tick();
      engine2.dispose();
      expect(other.isRunning, isFalse);
    });
  });
}

class _Budget implements AudLoadBudget {
  @override
  String get name => 'test voices';

  @override
  int limit = 0;

  @override
  int get reserve => 4;

  @override
  AudLoadBudgetUsage usage = const AudLoadBudgetUsage();
}

class _Timer implements Timer {
  _Timer(this.period, this._tick);

  final Duration period;
  final void Function(Timer timer) _tick;
  bool _active = true;

  void fire() => _tick(this);

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
