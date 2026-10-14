// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio_graph/aud_audio_graph.dart';

import 'aud_load_policy.dart';

// #############################################################################
/// What an `AudLoadGovernor` saw and did in its last period: the budget,
/// the units in use, the load and the problems since it started - the
/// numbers of the developer setting of the app (decision 4 of the plan of
/// ticket 29).
class AudLoadGovernorState {
  /// Creates the state.
  const AudLoadGovernorState({
    this.time = Duration.zero,
    this.budget = 0,
    this.units = 0,
    this.meanUnits = 0,
    this.load = const AudGraphLoad(),
    this.periodMean = 0,
    this.unitCost = 0,
    this.baseShare = 0,
    this.fit = 0,
    this.xruns = 0,
    this.overloads = 0,
    this.stolen = 0,
    this.stolenPerMinute = 0,
    this.action = AudLoadAction.hold,
    this.settled = false,
    this.settledAfter = Duration.zero,
  });

  // ...........................................................................
  /// The time the engine ran since the governor started.
  final Duration time;

  /// The units the budget allows.
  final int budget;

  /// The units in use at the end of the period.
  final int units;

  /// The mean units in use over the period.
  final double meanUnits;

  /// The load over the window of the governor, per render and over the
  /// runs that fill the device buffer.
  final AudGraphLoad load;

  /// The mean share of the block over the period.
  final double periodMean;

  /// The share of the block one unit adds; 0 while unknown.
  final double unitCost;

  /// The share of the block the renders take without units.
  final double baseShare;

  /// The units that keep the mean share at the target; 0 while unknown.
  final int fit;

  /// The xruns of the stream since the governor started.
  final int xruns;

  /// The runs of renders that fill the device buffer and took longer than
  /// it lasts, over the window of the governor.
  final int overloads;

  /// The units the owner of the budget stole since the governor started.
  final int stolen;

  /// The units stolen per minute over the last minute.
  final double stolenPerMinute;

  /// What the governor did with the budget in the period.
  final AudLoadAction action;

  /// Whether the budget has not fallen for the settle time.
  final bool settled;

  /// The time of the last lowering of the budget: how long the governor
  /// took to settle once [settled].
  final Duration settledAfter;

  // ...........................................................................
  /// The state as JSON.
  Map<String, Object> toJson() => {
    'timeMs': time.inMilliseconds,
    'budget': budget,
    'units': units,
    'meanUnits': meanUnits,
    'load': load.toJson(),
    'periodMean': periodMean,
    'unitCost': unitCost,
    'baseShare': baseShare,
    'fit': fit,
    'xruns': xruns,
    'overloads': overloads,
    'stolen': stolen,
    'stolenPerMinute': stolenPerMinute,
    'action': action.name,
    'settled': settled,
    'settledAfterMs': settledAfter.inMilliseconds,
  };

  @override
  String toString() => 'AudLoadGovernorState(${toJson()})';
}
