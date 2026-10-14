// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudLoadGovernorConfig', () {
    test('has the band of the measurements of ticket 29 by default', () {
      const config = AudLoadGovernorConfig();
      expect(config.period, const Duration(milliseconds: 100));
      expect(config.window, const Duration(seconds: 1));
      expect(config.target, 0.75);
      expect(config.upBelow, 0.72);
      expect(config.downAbove, 0.85);
      expect(config.floor, 8);
      expect(config.ceiling, 256);
      expect(config.step, 1);
      expect(config.holdAfterDown, const Duration(seconds: 2));
      expect(config.settleTime, const Duration(seconds: 10));
    });

    test('goes to JSON and a text', () {
      const config = AudLoadGovernorConfig(ceiling: 128);
      expect(config.toJson()['ceiling'], 128);
      expect(config.toJson()['periodMs'], 100);
      expect(config.toString(), contains('ceiling: 128'));
    });

    for (final (name, create) in [
      ('band', () => AudLoadGovernorConfig(target: 0.9)),
      ('floor', () => AudLoadGovernorConfig(floor: 0)),
      ('step', () => AudLoadGovernorConfig(step: 0)),
    ]) {
      test('refuses a broken $name', () {
        expect(
          create,
          throwsA(
            isA<AssertionError>().having((e) => e.message, 'message', name),
          ),
        );
      });
    }
  });
}
