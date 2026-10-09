// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  AudEngineNumbers numbers(List<int> commandToSound) => AudEngineNumbers(
    sampleRate: 48000,
    bufferFrames: 192,
    blocksRendered: 10,
    renderTimeMaxNs: 30000,
    renderTimeMeanNs: 12000.4,
    callbacks: 10,
    callbackTimeMaxNs: 40000,
    callbackTimeMeanNs: 20000.6,
    xruns: 1,
    lateCallbacks: 2,
    recoveries: 0,
    recoveryTimeMaxNs: 0,
    outputLatencyFrames: 384,
    commandToSoundNs: commandToSound,
  );

  group('AudEngineNumbers', () {
    test('summarizes the command-to-sound latencies', () {
      final measured = numbers([9000000, 5000000, 7000000]);
      expect(measured.commandToSoundMinNs, 5000000);
      expect(measured.commandToSoundMaxNs, 9000000);
      expect(measured.commandToSoundMeanNs, 7000000);
      final json = measured.toJson();
      expect(json['renderTimeMeanNs'], 12000);
      expect(json['callbackTimeMeanNs'], 20001);
      expect(json['commandToSoundMeanNs'], 7000000);
      expect(json['xruns'], 1);
      expect(measured.toString(), contains('lateCallbacks: 2'));
    });

    test('has no latency without a measurement', () {
      final empty = numbers(const []);
      expect(empty.commandToSoundMinNs, isNull);
      expect(empty.commandToSoundMaxNs, isNull);
      expect(empty.commandToSoundMeanNs, isNull);
      expect(empty.toJson()['commandToSoundMeanNs'], isNull);
    });
  });
}
