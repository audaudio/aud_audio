// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio_graph/aud_audio_graph.dart';
import 'package:aud_audio_io/aud_audio_io.dart';

// #############################################################################
/// What an `AudEngine` opens: the session, the output stream and the
/// graph.
class AudEngineConfig {
  /// Creates a configuration.
  ///
  /// - [backend] the platform's devices or the null device
  /// - [outputChannels] the channels of the output and of the graph
  /// - [sampleRate] the requested rate; 0 follows the device
  /// - [bufferFrames] the requested device buffer; 0 lets the platform choose
  /// - [maxFrames] the largest block the graph renders
  /// - [performanceMode] low latency, or power saving
  /// - [manualClock] null device: callbacks run only through
  ///   `AudIoStream.debugProcess`
  /// - [listen] take the notifications when the native side wakes; without
  ///   it, the client calls `AudEngine.pump`
  /// - [recoveryTimeout] how long the stream tries to recover a lost device
  /// - [graphOptions] the capacities and policies of the graph
  /// - [cacheBudget] the sample cache budget of the process in bytes; null
  ///   keeps the budget the process has (256 MB until one is set)
  const AudEngineConfig({
    this.backend = AudIoBackend.platform,
    this.outputChannels = 2,
    this.sampleRate = 0,
    this.bufferFrames = 0,
    this.maxFrames = 1024,
    this.performanceMode = AudIoPerformanceMode.lowLatency,
    this.manualClock = false,
    this.listen = true,
    this.recoveryTimeout = Duration.zero,
    this.graphOptions = const AudGraphOptions(),
    this.cacheBudget,
  }) : assert(outputChannels > 0, 'the graph needs output channels'),
       assert(
         cacheBudget == null || cacheBudget >= 0,
         'the budget is a number of bytes',
       );

  // ...........................................................................
  /// The platform's devices or the null device.
  final AudIoBackend backend;

  /// The channels of the output and of the graph; at least 1.
  final int outputChannels;

  /// The requested sample rate; 0 follows the device.
  final double sampleRate;

  /// The requested device buffer in frames; 0 lets the platform choose.
  final int bufferFrames;

  /// The largest block the graph renders.
  final int maxFrames;

  /// Low latency, or power saving.
  final AudIoPerformanceMode performanceMode;

  /// Null device: callbacks run only through `AudIoStream.debugProcess`.
  final bool manualClock;

  /// Whether the native notification threads wake the engine.
  final bool listen;

  /// How long the stream tries to recover a lost device; zero = 5 seconds.
  final Duration recoveryTimeout;

  /// The capacities and policies of the graph.
  final AudGraphOptions graphOptions;

  /// The sample cache budget of the process in bytes, which every engine
  /// and graph of the process shares (lifecycle-002, ticket 25): the
  /// samplers keep the samples they loaded and streamed within it. Null
  /// keeps the budget the process has; an engine with a budget sets it when
  /// it is created.
  final int? cacheBudget;

  /// The stream configuration: an output that holds the render function
  /// after a change of the format until the engine acknowledges it.
  AudIoStreamConfig get streamConfig => AudIoStreamConfig(
    outputChannels: outputChannels,
    sampleRate: sampleRate,
    bufferFrames: bufferFrames,
    maxFrames: maxFrames,
    performanceMode: performanceMode,
  );
}
