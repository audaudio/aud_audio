// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:ffi';

import 'package:aud_audio_core/aud_audio_core_bindings.dart' as core;

import 'aud_node_package.dart';

// #############################################################################
/// A DSP package on a native platform: its `aud_<package>_register`
/// function, which the engine calls with the host API of the graph.
///
/// ```dart
/// AudNativeNodePackage(
///   'aud_dsp_effects',
///   Native.addressOf(aud_dsp_effects_register),
/// )
/// ```
class AudNativeNodePackage implements AudNodePackage {
  /// The package [name] registering through [register].
  const AudNativeNodePackage(this.name, this.register);

  @override
  final String name;

  /// The `aud_<package>_register(const AudHostApi*)` function.
  final core.AudRegisterFunction register;

  /// Calls [register] with [host]; returns its result code.
  int registerWith(Pointer<core.AudHostApi> host) =>
      register.asFunction<int Function(Pointer<core.AudHostApi>)>()(host);
}
