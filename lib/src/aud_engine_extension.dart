// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'aud_engine.dart';

// #############################################################################
/// A part of an app that lives with an [AudEngine], e.g. the MIDI bridge of
/// `aud_audio_midi`, which feeds the graph from native threads.
///
/// The engine tells its extensions when it started, when it is about to
/// stop, when its timing starts again - a new format or route, a reset of
/// the time filter - and, synchronously, when it is about to dispose the
/// stream and the graph: an extension stops there everything that could
/// still touch the graph from another thread, since the graph's memory goes
/// right after.
abstract class AudEngineExtension {
  /// A name for reports.
  String get name;

  /// The engine started.
  void engineStarted(AudEngine engine) {}

  /// The engine is about to stop the stream and the graph.
  void engineStopping(AudEngine engine) {}

  /// The timing of the engine starts again; `AudEngine.timing` changes.
  void engineTimingChanged(AudEngine engine) {}

  /// The engine is about to dispose the stream and the graph. Runs
  /// synchronously; the extension may not touch the engine afterwards.
  void engineDisposing(AudEngine engine);
}
