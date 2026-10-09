// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio_io/aud_audio_io.dart';

import 'aud_engine.dart';
import 'aud_engine_config.dart';
import 'aud_engine_ffi.dart';
import 'aud_node_package.dart';

/// A native [AudEngine]; see its constructor.
AudEngine createEngine({
  required AudEngineConfig config,
  required List<AudNodePackage> packages,
  required AudIoPlatform? platform,
}) => AudEngineFfi(config: config, packages: packages, platform: platform);
