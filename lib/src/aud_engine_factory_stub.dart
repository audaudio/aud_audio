// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio_io/aud_audio_io.dart';

import 'aud_engine.dart';
import 'aud_engine_config.dart';
import 'aud_node_package.dart';

/// The engine where the native engine is not available (web: S5).
AudEngine createEngine({
  required AudEngineConfig config,
  required List<AudNodePackage> packages,
  required AudIoPlatform? platform,
}) => throw UnsupportedError('The engine needs the native platform (web: S5)');
