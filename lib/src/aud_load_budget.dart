// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// A budget of units of load - voices - that an `AudLoadGovernor` sets from
/// the load it measures: the voice budget of the sampler nodes of the
/// process now (`AudDspSampler.voiceBudget` of `aud_dsp_sampler`), the
/// voices of a synthesizer later. The owner of the budget keeps the units
/// below the limit, e.g. by stealing voices.
///
/// `aud_audio` knows no DSP package; the app binds the budget of a package
/// to this interface (decision 1 of the plan of ticket 29).
abstract interface class AudLoadBudget {
  /// A name for reports, e.g. `sampler voices`.
  String get name;

  /// The units the budget allows; 0 lifts the budget.
  int get limit;

  /// Sets the units the budget allows; 0 lifts the budget.
  set limit(int value);

  /// The units the owner keeps free below [limit]: the budget limits when
  /// the units in use reach `limit - reserve`.
  int get reserve;

  /// The units in use now and the counters since the start of the process.
  AudLoadBudgetUsage get usage;
}

// #############################################################################
/// The units an [AudLoadBudget] uses now and its counters, which count from
/// the start of the process and are never reset.
class AudLoadBudgetUsage {
  /// Creates the usage.
  const AudLoadBudgetUsage({
    this.units = 0,
    this.unitFrames = 0,
    this.stolen = 0,
  });

  // ...........................................................................
  /// The units in use now, e.g. the voices that sound.
  final int units;

  /// The units times the frames they rendered: the mean units over a time
  /// are the difference of two readings divided by the frames of the time.
  final int unitFrames;

  /// The units the owner stopped to keep its limits.
  final int stolen;

  // ...........................................................................
  /// The usage as JSON.
  Map<String, Object> toJson() => {
    'units': units,
    'unitFrames': unitFrames,
    'stolen': stolen,
  };

  @override
  String toString() =>
      'AudLoadBudgetUsage(units: $units, unitFrames: $unitFrames, '
      'stolen: $stolen)';
}
