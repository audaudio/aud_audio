// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:aud_audio_core/aud_audio_core.dart';
import 'package:aud_audio_graph/aud_audio_graph.dart';
import 'package:aud_audio_io/aud_audio_io.dart';

import 'aud_engine_config.dart';
import 'aud_engine_factory_stub.dart'
    if (dart.library.ffi) 'aud_engine_factory_native.dart'
    as platform_factory;
import 'aud_engine_numbers.dart';
import 'aud_engine_state.dart';
import 'aud_node_package.dart';

// #############################################################################
/// The Audanika Audio Engine: a graph of `aud_audio_graph` rendered by an
/// output stream of `aud_audio_io`, with the DSP packages of the app.
///
/// The engine opens a session and a stream, creates the graph and hands
/// the graph's render function to the stream. It keeps the lifecycle of
/// decision lifecycle-001: changes of the format or the route,
/// interruptions and lost devices all run one sequence - suspend the
/// graph, prepare it for the new rate and block size, resume it,
/// acknowledge the format to the stream - while the stream holds the
/// graph and plays silence. The transport, the graph and its nodes survive.
///
/// One API on every platform (web-001): on native platforms the engine is
/// an `AudEngineFfi` of `aud_audio_ffi.dart`; the web has no engine until
/// S5.
abstract interface class AudEngine {
  /// Opens the engine with [config]; [packages] register their node types
  /// at the start; [platform] replaces what the platform adds to the
  /// session (tests).
  factory AudEngine({
    AudEngineConfig config = const AudEngineConfig(),
    List<AudNodePackage> packages = const [],
    AudIoPlatform? platform,
  }) => platform_factory.createEngine(
    config: config,
    packages: packages,
    platform: platform,
  );

  // ...........................................................................
  /// The configuration.
  AudEngineConfig get config;

  /// The state.
  AudEngineState get state;

  /// Every state the engine enters, in order.
  Stream<AudEngineState> get states;

  /// The session of the engine.
  AudIoSession get session;

  /// The output stream that renders the graph.
  AudIoStream get stream;

  /// The graph.
  AudGraph get graph;

  /// The format of the stream.
  AudIoStreamFormat get format;

  /// The route the output plays through.
  AudIoRoute get route;

  /// The counters of the stream.
  AudIoCounters get counters;

  /// The statistics of the graph.
  AudGraphStats get stats;

  /// The node types the graph knows: its own and those of the packages.
  List<AudNodeDescriptor> get nodeTypes;

  /// The outcome of each package's registration; empty before [prepare].
  List<AudPackageRegistration> get registrations;

  /// Render time, xruns and the command-to-sound latencies measured so far.
  AudEngineNumbers get numbers;

  // ...........................................................................
  /// Registers the packages and prepares the graph for the format of the
  /// stream.
  void prepare();

  /// Starts the graph and the stream; prepares first if needed.
  void start();

  /// Stops the stream and the graph: start-up in reverse.
  void stop();

  /// Stops and releases the stream, the graph and the session.
  void dispose();

  // ...........................................................................
  /// Measures the command-to-sound latency once: from the host time of an
  /// empty transaction to the presentation time of the first block that
  /// renders it. The engine must be running.
  Future<int> measureCommandToSound({
    Duration timeout = const Duration(seconds: 2),
  });

  /// A text of the state, the format, the route and the numbers, for a
  /// report the user copies.
  String report();
}
