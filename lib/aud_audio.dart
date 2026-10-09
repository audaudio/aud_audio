// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The Audanika Audio Engine: [AudEngine] renders a graph of
/// `aud_audio_graph` through an output stream of `aud_audio_io` with the
/// node types of the DSP packages. One API on native platforms and the web
/// (web-001): this library imports no `dart:ffi`; `aud_audio_ffi.dart`
/// adds the native engine, the native node packages and the native parts
/// of the family.
library;

export 'package:aud_audio_core/aud_audio_core.dart';
export 'package:aud_audio_graph/aud_audio_graph.dart';
export 'package:aud_audio_io/aud_audio_io.dart';

export 'src/aud_audio_version.dart';
export 'src/aud_engine.dart';
export 'src/aud_engine_config.dart';
export 'src/aud_engine_numbers.dart';
export 'src/aud_engine_state.dart';
export 'src/aud_node_package.dart';
