// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio_ffi.dart';
// ignore: implementation_imports
import 'package:aud_audio/src/aud_engine_factory_native.dart';
import 'package:test/test.dart';

void main() {
  group('the native engine factory', () {
    test('creates an AudEngineFfi', () {
      final engine = createEngine(
        config: const AudEngineConfig(
          backend: AudIoBackend.nullDevice,
          manualClock: true,
        ),
        packages: const [],
        platform: null,
      );
      addTearDown(engine.dispose);
      expect(engine, isA<AudEngineFfi>());
    });
  });
}
