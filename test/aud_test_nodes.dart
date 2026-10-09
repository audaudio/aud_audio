// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:ffi';
import 'dart:io';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:aud_audio_core/aud_audio_core_bindings.dart'
    show AudRegisterFunctionFunction;

/// The test package `test_packages/aud_test_nodes`: a DSP package built
/// apart from the engine (`node scripts/test-native.js --library`) and
/// loaded as a library of its own, as the registry meets a third-party
/// package.
abstract final class AudTestNodes {
  static final DynamicLibrary _library = () {
    final result = Process.runSync('node', [
      'scripts/test-native.js',
      '--library',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Building aud_test_nodes failed: ${result.stderr}');
    }
    return DynamicLibrary.open((result.stdout as String).trim());
  }();

  static AudNativeNodePackage _package(String name, String symbol) =>
      AudNativeNodePackage(
        name,
        _library.lookup<NativeFunction<AudRegisterFunctionFunction>>(symbol),
      );

  /// Registers `aud.test.invert`, built against the ABI of the engine.
  static AudNativeNodePackage get current =>
      _package('aud_test_nodes', 'aud_test_nodes_register');

  /// Claims the next ABI major; the engine refuses it.
  static AudNativeNodePackage get future =>
      _package('aud_test_nodes_future', 'aud_test_nodes_future_register');
}
