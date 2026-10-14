// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:collection';

import 'aud_engine.dart';
import 'aud_engine_extension.dart';
import 'aud_engine_state.dart';
import 'aud_load_budget.dart';
import 'aud_load_governor_config.dart';
import 'aud_load_governor_state.dart';
import 'aud_load_policy.dart';

// #############################################################################
/// Sets an [AudLoadBudget] from the load the engine measures, so that
/// playing hard never drops out (ticket 29): an extension of the engine
/// that looks at the load every period on the control thread while the
/// engine runs.
///
/// Each period it reads the load gauge of the graph (`AudGraph.renderLoad`)
/// - the mean share of the block over the last second, and the p99 over
/// the runs of renders that fill the device buffer for the record -, the
/// xruns of the stream and the units of the budget, and lets its
/// [AudLoadPolicy] decide: down at once on an xrun or a mean share above
/// the band, up slowly below it. It starts from [AudLoadPolicy.budget]
/// - the budget the app learned on this device before, or the one of the
/// device's class (`AudDeviceClass.startUnits`). No Dart runs on the audio
/// thread: the owner of the budget keeps it there.
///
/// One governor per budget: two governors on one budget of the process
/// would overrule each other.
///
/// ```dart
/// final governor = AudLoadGovernor(
///   budget: samplerVoices,
///   start: AudDeviceClass.current().startUnits,
/// );
/// engine.addExtension(governor);
/// engine.start();
/// ```
class AudLoadGovernor extends AudEngineExtension {
  /// Creates the governor for [budget] with the settings [config], starting
  /// from [start] units (the ceiling of [config] if null). [periodic] and
  /// `clock` replace the timer and the clock in tests.
  AudLoadGovernor({
    required this.budget,
    this.config = const AudLoadGovernorConfig(),
    int? start,
    Timer Function(Duration period, void Function(Timer timer) tick)? periodic,
    this._clock,
  }) : policy = AudLoadPolicy(config: config, start: start),
       _periodic = periodic ?? Timer.periodic;

  // ...........................................................................
  /// The budget the governor sets.
  final AudLoadBudget budget;

  /// The settings.
  final AudLoadGovernorConfig config;

  /// The decisions of the governor.
  final AudLoadPolicy policy;

  /// The state after the last period.
  AudLoadGovernorState get state => _state;

  /// The state after each period.
  Stream<AudLoadGovernorState> get states => _states.stream;

  /// What the governor measured in the last period; recorded samples replay
  /// through an [AudLoadPolicy].
  AudLoadSample get lastSample => _lastSample;

  /// Whether the governor looks at the load: from the start of the engine
  /// to its stop.
  bool get isRunning => _timer != null;

  // ...........................................................................
  @override
  String get name => 'load governor of ${budget.name}';

  @override
  void engineStarted(AudEngine engine) {
    _engine = engine;
    budget.limit = policy.budget;
    _baseline(engine);
    _timer?.cancel();
    _timer = _periodic(config.period, (_) => tick());
  }

  @override
  void engineStopping(AudEngine engine) => _stop();

  @override
  void engineTimingChanged(AudEngine engine) {
    policy.timingChanged();
    _baseline(engine);
  }

  @override
  void engineDisposing(AudEngine engine) {
    _stop();
    _engine = null;
    unawaited(_states.close());
  }

  // ...........................................................................
  /// Looks at the load once and sets the budget; the timer calls it every
  /// period while the engine runs.
  void tick() {
    final engine = _engine;
    if (engine == null || engine.state != AudEngineState.running) return;
    final now = _now();
    final elapsed = now - _lastTime;
    if (elapsed <= Duration.zero) return;
    // The policy steers the mean share; the p99 and the overloads of the
    // runs that fill the device buffer go along for the record (the
    // measurements of the Galaxy Tab S4 in ticket 29).
    final buffer = engine.format.bufferFrames;
    final window = engine.graph.renderLoad(config.window, buffer);
    final period = engine.graph.renderLoad(elapsed, buffer);
    final xruns = engine.counters.xruns;
    final usage = budget.usage;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final frames = engine.format.sampleRate * seconds;
    final sample = AudLoadSample(
      time: now,
      periodMean: period.mean,
      windowMean: window.mean,
      p99: window.bufferP99,
      max: window.bufferMax,
      meanUnits: frames > 0
          ? (usage.unitFrames - _usage.unitFrames) / frames
          : 0,
      units: usage.units,
      xruns: xruns - _xruns,
      overloads: period.bufferOverloads,
      stolen: usage.stolen - _usage.stolen,
    );
    final action = policy.step(sample, reserve: budget.reserve);
    if (budget.limit != policy.budget) budget.limit = policy.budget;
    _total = (
      xruns: _total.xruns + sample.xruns,
      overloads: _total.overloads + sample.overloads,
      stolen: _total.stolen + sample.stolen,
    );
    _stolenHistory.add((time: now, stolen: _total.stolen));
    while (now - _stolenHistory.first.time > const Duration(minutes: 1)) {
      _stolenHistory.removeFirst();
    }
    _lastTime = now;
    _xruns = xruns;
    _usage = usage;
    _lastSample = sample;
    _state = AudLoadGovernorState(
      time: now,
      budget: policy.budget,
      units: usage.units,
      meanUnits: sample.meanUnits,
      load: window,
      periodMean: period.mean,
      unitCost: policy.unitCost ?? 0,
      baseShare: policy.baseShare,
      fit: policy.fit ?? 0,
      xruns: _total.xruns,
      overloads: _total.overloads,
      stolen: _total.stolen,
      stolenPerMinute: _stolenPerMinute(now),
      action: action,
      settled: policy.settled(now),
      settledAfter: policy.settledAfter,
    );
    _states.add(_state);
  }

  // ######################
  // Private
  // ######################

  final Timer Function(Duration period, void Function(Timer timer) tick)
  _periodic;
  final Duration Function()? _clock;
  final Stopwatch _stopwatch = Stopwatch();
  final StreamController<AudLoadGovernorState> _states =
      StreamController.broadcast(sync: true);
  final Queue<({Duration time, int stolen})> _stolenHistory = Queue();

  AudEngine? _engine;
  Timer? _timer;
  AudLoadGovernorState _state = const AudLoadGovernorState();
  AudLoadSample _lastSample = const AudLoadSample(time: Duration.zero);
  Duration _lastTime = Duration.zero;
  int _xruns = 0;
  AudLoadBudgetUsage _usage = const AudLoadBudgetUsage();
  ({int xruns, int overloads, int stolen}) _total = (
    xruns: 0,
    overloads: 0,
    stolen: 0,
  );

  Duration _now() => _clock?.call() ?? _stopwatch.elapsed;

  /// Takes the counters as they are now as the start of the next period.
  void _baseline(AudEngine engine) {
    _stopwatch.start();
    _lastTime = _now();
    _xruns = engine.counters.xruns;
    _usage = budget.usage;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
  }

  double _stolenPerMinute(Duration now) {
    final first = _stolenHistory.first;
    final span = now - first.time;
    if (span < const Duration(seconds: 1)) return 0;
    final stolen = _total.stolen - first.stolen;
    return stolen * Duration.microsecondsPerMinute / span.inMicroseconds;
  }
}
