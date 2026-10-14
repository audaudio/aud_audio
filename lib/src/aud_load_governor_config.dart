// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The settings of an `AudLoadGovernor` (decision 3 of the plan of ticket
/// 29, revised by the measurements on the Galaxy Tab S4): every [period] it
/// reads the mean share of the block the renders took over the last
/// [window]; it lowers the budget at once on an xrun or a mean above
/// [downAbove], and raises it by [step] only while the mean stays below
/// [upBelow] and the budget limits. Its estimate of the cost of a unit aims
/// the mean at [target].
class AudLoadGovernorConfig {
  /// Creates the settings.
  const AudLoadGovernorConfig({
    this.period = const Duration(milliseconds: 100),
    this.window = const Duration(seconds: 1),
    this.target = 0.75,
    this.upBelow = 0.72,
    this.downAbove = 0.85,
    this.floor = 8,
    this.ceiling = 256,
    this.step = 1,
    this.holdAfterDown = const Duration(seconds: 2),
    this.settleTime = const Duration(seconds: 10),
  }) : assert(upBelow <= target && target <= downAbove),
       assert(0 < floor && floor <= ceiling),
       assert(step > 0);

  // ...........................................................................
  /// How often the governor looks at the load.
  final Duration period;

  /// The time the mean share spans.
  final Duration window;

  /// The mean share of the block the governor aims at with its estimate of
  /// the cost of a unit.
  final double target;

  /// The mean share below which the governor may raise the budget.
  final double upBelow;

  /// The mean share above which the governor lowers the budget at once.
  final double downAbove;

  /// The fewest units the governor allows.
  final int floor;

  /// The most units the governor allows.
  final int ceiling;

  /// The units the governor adds per period while it raises the budget.
  final int step;

  /// How long the governor does not raise the budget after it lowered it.
  final Duration holdAfterDown;

  /// How long the budget must not fall before the governor counts as
  /// settled.
  final Duration settleTime;

  // ...........................................................................
  /// The settings as JSON.
  Map<String, Object> toJson() => {
    'periodMs': period.inMilliseconds,
    'windowMs': window.inMilliseconds,
    'target': target,
    'upBelow': upBelow,
    'downAbove': downAbove,
    'floor': floor,
    'ceiling': ceiling,
    'step': step,
    'holdAfterDownMs': holdAfterDown.inMilliseconds,
    'settleTimeMs': settleTime.inMilliseconds,
  };

  @override
  String toString() => 'AudLoadGovernorConfig(${toJson()})';
}
