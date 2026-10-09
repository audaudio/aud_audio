// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The states of an `AudEngine` (lifecycle-001); every transition is
/// acknowledged on `AudEngine.states`.
enum AudEngineState {
  /// The session, the stream and the graph exist; nothing is prepared.
  created,

  /// The packages are registered and the graph is prepared for the format
  /// of the stream.
  prepared,

  /// The stream calls the graph.
  running,

  /// An interruption, a lost device or a change of the format holds the
  /// graph; the engine resumes on its own.
  suspended,

  /// The stream and the graph are stopped; `start` runs them again.
  stopped,

  /// Everything is released.
  disposed,
}
