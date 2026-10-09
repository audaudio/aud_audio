// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudEngineState', () {
    test('lists the states of lifecycle-001 in order', () {
      expect(AudEngineState.values.map((s) => s.name), [
        'created',
        'prepared',
        'running',
        'suspended',
        'stopped',
        'disposed',
      ]);
    });
  });
}
