// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:ffi';

import 'package:aud_audio_core/aud_audio_core_bindings.dart' as core;
import 'package:aud_audio_core/aud_audio_core_ffi.dart';
import 'package:aud_audio_graph/aud_audio_graph_ffi.dart';
import 'package:aud_audio_io/aud_audio_io_ffi.dart';

import 'aud_engine.dart';
import 'aud_engine_config.dart';
import 'aud_engine_numbers.dart';
import 'aud_engine_state.dart';
import 'aud_native_node_package.dart';
import 'aud_node_package.dart';

// #############################################################################
/// The native [AudEngine]: the glue runs in Dart on the control thread
/// (decision 1 of ticket 22); the stream's format hold keeps the audio
/// thread away from the graph while it is prepared again.
class AudEngineFfi implements AudEngine {
  /// Opens the session and creates the graph, then opens the stream with
  /// the graph's render function; see [AudEngine.new].
  AudEngineFfi({
    this.config = const AudEngineConfig(),
    List<AudNodePackage> packages = const [],
    AudIoPlatform? platform,
  }) : _packages = List.unmodifiable(packages) {
    session = AudIoSessionFfi(
      backend: config.backend,
      manualClock: config.manualClock,
      recoveryTimeout: config.recoveryTimeout,
      listen: config.listen,
      platform: platform,
    );
    graph = AudGraphFfi(
      maxFrames: config.maxFrames,
      outputChannels: [config.outputChannels],
      options: config.graphOptions,
      listen: config.listen,
    );
    stream = session.open(
      config.streamConfig,
      render: renderFunction,
      user: graph.pointer.cast(),
    );
    _subscription = stream.notifications.listen(_onNotification);
  }

  /// The render function of the graph as the stream calls it.
  static core.AudRenderFunction get renderFunction =>
      Native.addressOf<NativeFunction<core.AudRenderFunctionFunction>>(
        aud_graph_render,
      );

  // ...........................................................................
  @override
  final AudEngineConfig config;

  @override
  late final AudIoSessionFfi session;

  @override
  late final AudIoStreamFfi stream;

  @override
  late final AudGraphFfi graph;

  @override
  AudEngineState get state => _state;

  @override
  Stream<AudEngineState> get states => _states.stream;

  @override
  AudIoStreamFormat get format => stream.format;

  @override
  AudIoRoute get route {
    final id = format.outputDeviceId;
    for (final device in session.devices) {
      if (device.id == id) return device.route;
    }
    return AudIoRoute.unknown;
  }

  @override
  AudIoCounters get counters => stream.counters;

  @override
  AudGraphStats get stats => graph.stats;

  @override
  List<AudNodeDescriptor> get nodeTypes => graph.nodeTypes;

  @override
  List<AudPackageRegistration> get registrations =>
      List.unmodifiable(_registrations);

  @override
  AudEngineNumbers get numbers {
    final stats = graph.stats;
    final counters = stream.counters;
    final format = stream.format;
    return AudEngineNumbers(
      sampleRate: format.sampleRate,
      bufferFrames: format.bufferFrames,
      blocksRendered: stats.blocksRendered,
      renderTimeMaxNs: stats.renderTimeMaxNs,
      renderTimeMeanNs: stats.blocksRendered == 0
          ? 0
          : stats.renderTimeSumNs / stats.blocksRendered,
      callbacks: counters.callbacks,
      callbackTimeMaxNs: counters.callbackTimeMaxNs,
      callbackTimeMeanNs: counters.callbackTimeMeanNs,
      xruns: counters.xruns,
      lateCallbacks: counters.lateCallbacks,
      recoveries: counters.recoveries,
      recoveryTimeMaxNs: counters.recoveryTimeMaxNs,
      outputLatencyFrames: counters.lastTime.outputLatencyFrames,
      commandToSoundNs: List.unmodifiable(_commandToSound),
    );
  }

  // ...........................................................................
  @override
  void prepare() {
    _checkNotDisposed();
    if (_state != AudEngineState.created && _state != AudEngineState.stopped) {
      throw StateError('Cannot prepare the engine when it is ${_state.name}');
    }
    if (_registrations.isEmpty) _register();
    final format = stream.format;
    graph.prepare(sampleRate: format.sampleRate, maxFrames: format.maxFrames);
    stream.acknowledge(format.generation);
    _enter(AudEngineState.prepared);
  }

  @override
  void start() {
    _checkNotDisposed();
    if (_state == AudEngineState.running ||
        _state == AudEngineState.suspended) {
      return;
    }
    if (_state != AudEngineState.prepared) prepare();
    graph.start();
    stream.start();
    _enter(AudEngineState.running);
  }

  @override
  void stop() {
    _checkNotDisposed();
    if (_state != AudEngineState.running &&
        _state != AudEngineState.suspended) {
      return;
    }
    stream.stop();
    graph.stop();
    _enter(AudEngineState.stopped);
  }

  @override
  void dispose() {
    if (_state == AudEngineState.disposed) return;
    stop();
    unawaited(_subscription.cancel());
    stream.close();
    graph.dispose();
    session.dispose();
    _enter(AudEngineState.disposed);
    unawaited(_states.close());
  }

  // ...........................................................................
  @override
  Future<int> measureCommandToSound({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _checkNotDisposed();
    if (_state != AudEngineState.running) {
      throw StateError('Measure only while the engine is running');
    }
    final adopted = graph.notifications
        .where((n) => n is AudRevisionAdoptedNotification)
        .cast<AudRevisionAdoptedNotification>();
    final sentNs = AudClock.nowNs();
    final revision = graph.transaction((_) {});
    final notification = await adopted
        .firstWhere((n) => n.revision >= revision)
        .timeout(timeout);
    final latency =
        presentationTimeNs(notification.samplePosition, stream.counters) -
        sentNs;
    _commandToSound.add(latency);
    return latency;
  }

  /// The host time at which the frame at [samplePosition] reaches the
  /// output, extrapolated from the time of the last callback in [counters].
  static int presentationTimeNs(int samplePosition, AudIoCounters counters) {
    final time = counters.lastTime;
    final frames = samplePosition - time.samplePosition;
    return time.hostTimeNs + (frames * 1e9 / time.sampleRate).round();
  }

  @override
  String report() {
    final format = stream.format;
    final buffer = StringBuffer()
      ..writeln('aud_audio engine report')
      ..writeln('state: ${_state.name}')
      ..writeln('backend: ${format.backend}')
      ..writeln('route: ${route.name}')
      ..writeln(
        'format: ${format.sampleRate.toStringAsFixed(0)} Hz, '
        '${format.outputChannels} out, buffer ${format.bufferFrames}, '
        'burst ${format.burstFrames}, max block ${format.maxFrames}, '
        'generation ${format.generation}',
      )
      ..writeln(
        'packages: ${_registrations.map((r) => '${r.package} '
            '${r.result}').join(', ')}',
      );
    for (final MapEntry(:key, :value) in numbers.toJson().entries) {
      buffer.writeln('$key: $value');
    }
    return buffer.toString();
  }

  // ######################
  // Private
  // ######################

  final List<AudNodePackage> _packages;
  final List<AudPackageRegistration> _registrations = [];
  final List<int> _commandToSound = [];
  final StreamController<AudEngineState> _states =
      StreamController<AudEngineState>.broadcast();
  late final StreamSubscription<AudIoNotification> _subscription;
  AudEngineState _state = AudEngineState.created;

  void _enter(AudEngineState state) {
    _state = state;
    _states.add(state);
  }

  void _checkNotDisposed() {
    if (_state == AudEngineState.disposed) {
      throw StateError('The engine is disposed');
    }
  }

  // ...........................................................................
  void _register() {
    for (final package in _packages) {
      final code = package is AudNativeNodePackage
          ? package.registerWith(graph.hostApi)
          : AUD_ERROR_UNSUPPORTED;
      _registrations.add(AudPackageRegistration(package.name, code));
    }
  }

  // ...........................................................................
  void _onNotification(AudIoNotification notification) {
    switch (notification.type) {
      case AudIoNotificationType.interrupted:
      case AudIoNotificationType.disconnected:
        _suspend();
      case AudIoNotificationType.formatChanged:
      case AudIoNotificationType.routeChanged:
      case AudIoNotificationType.resumed:
      case AudIoNotificationType.recovered:
        _reprepare(notification.generation);
      default:
        break;
    }
  }

  void _suspend() {
    if (_state != AudEngineState.running) return;
    graph.suspend();
    _enter(AudEngineState.suspended);
  }

  /// The one sequence of lifecycle-001: suspend, prepare for the format of
  /// [generation], resume, acknowledge.
  void _reprepare(int generation) {
    final format = stream.format;
    if (_state == AudEngineState.running ||
        _state == AudEngineState.suspended) {
      _suspend();
      graph.prepare(sampleRate: format.sampleRate, maxFrames: format.maxFrames);
      graph.resume();
      _enter(AudEngineState.running);
    } else if (_state == AudEngineState.prepared) {
      graph.prepare(sampleRate: format.sampleRate, maxFrames: format.maxFrames);
    }
    stream.acknowledge(
      generation > format.generation ? generation : format.generation,
    );
  }
}
