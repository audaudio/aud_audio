// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
// ignore: implementation_imports
import 'package:aud_audio/src/aud_engine_factory_stub.dart';
import 'package:test/test.dart';

void main() {
  group('the engine factory without the native platform', () {
    test('is unsupported', () {
      expect(
        () => createEngine(
          config: const AudEngineConfig(),
          packages: const [],
          platform: null,
        ),
        throwsUnsupportedError,
      );
    });
  });
}
