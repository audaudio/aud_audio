// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudLoadGovernorState', () {
    test('is empty by default', () {
      const state = AudLoadGovernorState();
      expect(state.time, Duration.zero);
      expect(state.budget, 0);
      expect(state.load.renders, 0);
      expect(state.action, AudLoadAction.hold);
      expect(state.settled, isFalse);
    });

    test('goes to JSON and a text', () {
      const state = AudLoadGovernorState(
        time: Duration(seconds: 3),
        budget: 48,
        units: 40,
        meanUnits: 38.5,
        periodMean: 0.31,
        unitCost: 0.008,
        baseShare: 0.04,
        fit: 52,
        xruns: 1,
        overloads: 2,
        stolen: 30,
        stolenPerMinute: 120,
        action: AudLoadAction.down,
        settled: true,
        settledAfter: Duration(seconds: 2),
      );
      final json = state.toJson();
      expect(json['timeMs'], 3000);
      expect(json['budget'], 48);
      expect(json['units'], 40);
      expect(json['meanUnits'], 38.5);
      expect(json['load'], isA<Map<String, Object?>>());
      expect(json['periodMean'], 0.31);
      expect(json['unitCost'], 0.008);
      expect(json['baseShare'], 0.04);
      expect(json['fit'], 52);
      expect(json['xruns'], 1);
      expect(json['overloads'], 2);
      expect(json['stolen'], 30);
      expect(json['stolenPerMinute'], 120);
      expect(json['action'], 'down');
      expect(json['settled'], true);
      expect(json['settledAfterMs'], 2000);
      expect(state.toString(), contains('budget: 48'));
    });
  });
}
