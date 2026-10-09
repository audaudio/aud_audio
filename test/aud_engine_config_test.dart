// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudEngineConfig', () {
    test('streamConfig is an output that holds a new format', () {
      const config = AudEngineConfig(
        outputChannels: 1,
        sampleRate: 44100,
        bufferFrames: 192,
        maxFrames: 256,
        performanceMode: AudIoPerformanceMode.powerSaving,
      );
      final stream = config.streamConfig;
      expect(stream.direction, AudIoDirection.output);
      expect(stream.outputChannels, 1);
      expect(stream.sampleRate, 44100);
      expect(stream.bufferFrames, 192);
      expect(stream.maxFrames, 256);
      expect(stream.performanceMode, AudIoPerformanceMode.powerSaving);
      expect(stream.followFormat, isFalse);
    });

    test('defaults to the platform, stereo and the device rate', () {
      const config = AudEngineConfig();
      expect(config.backend, AudIoBackend.platform);
      expect(config.outputChannels, 2);
      expect(config.sampleRate, 0);
      expect(config.listen, isTrue);
      expect(config.recoveryTimeout, Duration.zero);
    });
  });
}
