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
    cacheBytes: 1000,
    cacheBudget: 4000,
    cacheTrimmed: 500,
    loadsRunning: 1,
    loadsFailed: 2,
    loadTimeMaxNs: 3000000,
  );

  group('AudEngineNumbers', () {
    group('commandToSoundMinNs, commandToSoundMeanNs, commandToSoundMaxNs', () {
      test('summarize the command-to-sound latencies', () {
        final measured = numbers([9000000, 5000000, 7000000]);
        expect(
          (
            measured.commandToSoundMinNs,
            measured.commandToSoundMeanNs,
            measured.commandToSoundMaxNs,
          ),
          (5000000, 7000000, 9000000),
        );
      });

      test('are null without a measurement', () {
        final empty = numbers(const []);
        expect(
          (
            empty.commandToSoundMinNs,
            empty.commandToSoundMeanNs,
            empty.commandToSoundMaxNs,
          ),
          (null, null, null),
        );
      });
    });

    group('toJson()', () {
      // The JSON of the numbers with the latencies 9, 5 and 7 ms.
      const measured = <String, Object?>{
        'sampleRate': 48000,
        'bufferFrames': 192,
        'blocksRendered': 10,
        'renderTimeMaxNs': 30000,
        'renderTimeMeanNs': 12000,
        'callbacks': 10,
        'callbackTimeMaxNs': 40000,
        'callbackTimeMeanNs': 20001,
        'xruns': 1,
        'lateCallbacks': 2,
        'recoveries': 0,
        'recoveryTimeMaxNs': 0,
        'outputLatencyFrames': 384,
        'commandToSoundNs': [9000000, 5000000, 7000000],
        'commandToSoundMinNs': 5000000,
        'commandToSoundMeanNs': 7000000,
        'commandToSoundMaxNs': 9000000,
        'cacheBytes': 1000,
        'cacheBudget': 4000,
        'cacheTrimmed': 500,
        'loadsRunning': 1,
        'loadsFailed': 2,
        'loadTimeMaxNs': 3000000,
      };

      test('holds every number and rounds the means', () {
        expect(numbers([9000000, 5000000, 7000000]).toJson(), measured);
      });

      test('has no latency without a measurement', () {
        expect(numbers(const []).toJson(), {
          ...measured,
          'commandToSoundNs': <int>[],
          'commandToSoundMinNs': null,
          'commandToSoundMeanNs': null,
          'commandToSoundMaxNs': null,
        });
      });
    });

    group('toString()', () {
      test('shows the JSON', () {
        final measured = numbers(const [5000000]);
        expect(measured.toString(), 'AudEngineNumbers(${measured.toJson()})');
      });
    });
  });
}
