// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudLoadBudgetUsage', () {
    test('is empty by default', () {
      const usage = AudLoadBudgetUsage();
      expect(usage.units, 0);
      expect(usage.unitFrames, 0);
      expect(usage.stolen, 0);
    });

    test('goes to JSON and a text', () {
      const usage = AudLoadBudgetUsage(units: 3, unitFrames: 480, stolen: 2);
      expect(usage.toJson(), {'units': 3, 'unitFrames': 480, 'stolen': 2});
      expect(
        usage.toString(),
        'AudLoadBudgetUsage(units: 3, unitFrames: 480, stolen: 2)',
      );
    });
  });
}
