// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudEngine', () {
    test('opens the engine of the platform', () {
      final engine = AudEngine(
        config: const AudEngineConfig(
          backend: AudIoBackend.nullDevice,
          manualClock: true,
        ),
      );
      addTearDown(engine.dispose);
      expect(engine.state, AudEngineState.created);
      expect(engine.config.outputChannels, 2);
      expect(engine.format.outputChannels, 2);
      expect(engine.graph.outputChannels, [2]);
      expect(engine.session.backendName, 'null');
      expect(engine.stream.state, AudIoState.stopped);
    });
  });
}
