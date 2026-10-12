// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('AudEngineExtension', () {
    test('needs only a name and engineDisposing; the rest does nothing', () {
      final engine = AudEngineFfi(
        config: const AudEngineConfig(
          backend: AudIoBackend.nullDevice,
          outputChannels: 1,
          maxFrames: 256,
          manualClock: true,
        ),
      );
      final extension = _Minimal();
      engine.addExtension(extension);
      engine.start();
      extension.engineTimingChanged(engine);
      engine.stop();
      expect(extension.disposed, 0);
      engine.dispose();
      expect(extension.disposed, 1);
      expect(extension.name, 'minimal');
    });
  });
}

class _Minimal extends AudEngineExtension {
  int disposed = 0;

  @override
  String get name => 'minimal';

  @override
  void engineDisposing(AudEngine engine) => disposed += 1;
}
