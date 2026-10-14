// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math' as math;

import 'aud_load_governor_config.dart';

// #############################################################################
/// What an [AudLoadPolicy] did with the budget in a period.
enum AudLoadAction {
  /// The budget stayed.
  hold,

  /// The budget fell: an xrun or a mean share above the band.
  down,

  /// The budget rose by a step: the mean share below the band while it
  /// limits.
  up,
}

// #############################################################################
/// What an `AudLoadGovernor` measured in a period: the shares of the block
/// the renders took, the problems of the stream and the units in use.
class AudLoadSample {
  /// Creates the sample.
  const AudLoadSample({
    required this.time,
    this.periodMean = 0,
    this.windowMean = 0,
    this.p99 = 0,
    this.max = 0,
    this.meanUnits = 0,
    this.units = 0,
    this.xruns = 0,
    this.overloads = 0,
    this.stolen = 0,
  });

  // ...........................................................................
  /// The time since the governor started.
  final Duration time;

  /// The mean share of the block over the period.
  final double periodMean;

  /// The mean share of the block over the window of the governor: the load
  /// the policy steers.
  final double windowMean;

  /// The p99 share over the window of the runs of renders that fill the
  /// device buffer (`AudGraphLoad.bufferP99`); recorded, not steered by.
  final double p99;

  /// The largest share of such a run over the window.
  final double max;

  /// The mean units in use over the period.
  final double meanUnits;

  /// The units in use at the end of the period.
  final int units;

  /// The xruns of the stream in the period.
  final int xruns;

  /// The runs of renders that fill the device buffer and took longer than
  /// it lasts, in the period.
  final int overloads;

  /// The units the owner of the budget stole in the period.
  final int stolen;

  // ...........................................................................
  /// The sample as JSON.
  Map<String, Object> toJson() => {
    'timeMs': time.inMilliseconds,
    'periodMean': periodMean,
    'windowMean': windowMean,
    'p99': p99,
    'max': max,
    'meanUnits': meanUnits,
    'units': units,
    'xruns': xruns,
    'overloads': overloads,
    'stolen': stolen,
  };

  /// A sample from [json], the output of [toJson]: recorded loads replay
  /// through a policy (step 4 of the plan of ticket 29).
  factory AudLoadSample.fromJson(Map<String, Object?> json) {
    double d(String key) => (json[key] as num? ?? 0).toDouble();
    int i(String key) => (json[key] as num? ?? 0).toInt();
    return AudLoadSample(
      time: Duration(milliseconds: i('timeMs')),
      periodMean: d('periodMean'),
      windowMean: d('windowMean'),
      p99: d('p99'),
      max: d('max'),
      meanUnits: d('meanUnits'),
      units: i('units'),
      xruns: i('xruns'),
      overloads: i('overloads'),
      stolen: i('stolen'),
    );
  }

  @override
  String toString() => 'AudLoadSample(${toJson()})';
}

// #############################################################################
/// The decisions of an `AudLoadGovernor` without timers and engine: one
/// [step] per period from an [AudLoadSample] (decision 3 of the plan of
/// ticket 29, revised by the measurements on the Galaxy Tab S4).
///
/// The policy steers the mean share of the block the renders take over the
/// window - the sustained load, which tells when a stream drops out; the
/// p99 does not, since a burst of note-ons makes a few renders long at any
/// number of voices and the device buffer absorbs them. From the periods
/// in which units sound it fits a line through the mean shares over the
/// units in use, with a memory of a few seconds: the share without units
/// ([baseShare]) and the share each unit adds ([unitCost]); from them it
/// computes the units that keep the mean at the target ([fit]).
///
/// It lowers the budget at once on an xrun - by a step and to three
/// quarters of the units in use - and on a mean above the band - by a step
/// and to [fit], but no deeper than the units in use scaled to the target.
/// After a lowering the mean counts again once the window holds only
/// renders after it. It raises the budget by a step only while the mean
/// stays below the band, the budget limits the units and no lowering
/// happened for a while. A budget that has not fallen for the settle time
/// is [settled].
class AudLoadPolicy {
  /// Creates the policy with the budget [start], clamped to the floor and
  /// the ceiling of [config].
  AudLoadPolicy({this.config = const AudLoadGovernorConfig(), int? start})
    : _budget = (start ?? config.ceiling).clamp(config.floor, config.ceiling);

  // ...........................................................................
  /// The settings.
  final AudLoadGovernorConfig config;

  /// The units the budget allows now.
  int get budget => _budget;

  /// The share of the block one unit adds; null until learned.
  double? get unitCost => _unitCost;

  /// The share of the block the renders take without units; 0 until
  /// learned.
  double get baseShare => _baseShare ?? 0;

  /// The units that keep the mean share at the target; null while the cost
  /// of a unit is unknown.
  int? get fit {
    final cost = _unitCost;
    if (cost == null || cost < _minCost) return null;
    // A whole unit that rounding left a hair below counts.
    final units = (config.target - baseShare) / cost + 1e-9;
    return units.floor().clamp(config.floor, config.ceiling);
  }

  /// When the budget last fell; null if it never did.
  Duration? get lastDown => _lastDown;

  /// Whether the budget has not fallen for the settle time at [time].
  bool settled(Duration time) =>
      time - (_lastDown ?? Duration.zero) >= config.settleTime;

  /// The time the budget last fell, or zero if it never did: the time the
  /// governor took to settle once it is [settled].
  Duration get settledAfter => _lastDown ?? Duration.zero;

  // ...........................................................................
  /// Takes the [sample] of a period and sets the [budget]; [reserve] is the
  /// units the owner of the budget keeps free below it.
  AudLoadAction step(AudLoadSample sample, {int reserve = 0}) {
    _learn(sample);
    final sinceDown = _lastDown == null ? null : sample.time - _lastDown!;
    // The window still holds renders from before the last lowering: its
    // mean counts again once the window has passed, xruns at once.
    final fresh = sinceDown == null || sinceDown >= config.window;
    if (sample.xruns > 0) return _down(sample, xrun: true);
    if (fresh && sample.windowMean > config.downAbove) {
      return _down(sample, xrun: false);
    }
    final limits = sample.stolen > 0 || sample.units >= _budget - reserve - 1;
    final held = sinceDown != null && sinceDown < config.holdAfterDown;
    if (sample.windowMean < config.upBelow && limits && !held) return _up();
    return AudLoadAction.hold;
  }

  /// Forgets what the policy learned about the cost of a unit: a new format
  /// or block size changes the shares. The budget stays.
  void timingChanged() {
    _unitCost = null;
    _baseShare = null;
    _n = _sumUnits = _sumShares = _sumUnits2 = _sumUnitsShares = 0;
  }

  // ######################
  // Private
  // ######################

  /// The weight a period keeps per period: a memory of about five seconds
  /// of periods of 100 ms.
  static const double _forget = 0.98;

  /// The spread of the units in use below which the line is not fitted
  /// again: two units.
  static const double _minUnitsVariance = 4;
  static const double _minCost = 1e-6;
  static const double _xrunCut = 0.75;

  int _budget;
  double? _unitCost;
  double? _baseShare;
  Duration? _lastDown;

  // The weighted sums of the line: periods, units, shares, units squared,
  // units times shares.
  double _n = 0;
  double _sumUnits = 0;
  double _sumShares = 0;
  double _sumUnits2 = 0;
  double _sumUnitsShares = 0;

  void _learn(AudLoadSample sample) {
    final units = sample.meanUnits;
    final share = sample.periodMean;
    if (share <= 0 || units < 1) return;
    _n = _n * _forget + 1;
    _sumUnits = _sumUnits * _forget + units;
    _sumShares = _sumShares * _forget + share;
    _sumUnits2 = _sumUnits2 * _forget + units * units;
    _sumUnitsShares = _sumUnitsShares * _forget + units * share;
    final meanUnits = _sumUnits / _n;
    final meanShare = _sumShares / _n;
    final variance = _sumUnits2 / _n - meanUnits * meanUnits;
    if (variance < _minUnitsVariance) return;
    final covariance = _sumUnitsShares / _n - meanUnits * meanShare;
    final cost = math.max(covariance / variance, 0.0);
    _unitCost = cost;
    _baseShare = (meanShare - cost * meanUnits).clamp(0.0, 1.0);
  }

  AudLoadAction _down(AudLoadSample sample, {required bool xrun}) {
    final inUse = math.max(sample.meanUnits, sample.units.toDouble());
    var next = _budget - config.step;
    if (inUse >= config.floor) {
      if (xrun) {
        next = math.min(next, (inUse * _xrunCut).floor());
      } else {
        // To the fit, but no deeper than the units in use scaled to the
        // target: with a share without units that is not 0 this cuts less
        // than needed, so a fit that the noise of a flat load put too low
        // does not cut deep; the next window cuts again if need be.
        final scaled = (inUse * config.target / sample.windowMean).floor();
        next = math.min(next, math.max(fit ?? 0, scaled));
      }
    }
    final action = _set(next);
    if (action == AudLoadAction.down) _lastDown = sample.time;
    return action;
  }

  AudLoadAction _up() => _set(_budget + config.step);

  AudLoadAction _set(int next) {
    final clamped = next.clamp(config.floor, config.ceiling);
    final action = clamped < _budget
        ? AudLoadAction.down
        : clamped > _budget
        ? AudLoadAction.up
        : AudLoadAction.hold;
    _budget = clamped;
    return action;
  }
}
