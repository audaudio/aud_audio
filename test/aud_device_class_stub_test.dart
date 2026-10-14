// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio.dart';
import 'package:aud_audio/src/aud_device_class_stub.dart' as stub;
import 'package:test/test.dart';

void main() {
  group('AudDeviceProbeStub', () {
    test('reads nothing', () {
      final probe = stub.createProbe();
      expect(probe, isA<stub.AudDeviceProbeStub>());
      expect(probe.os, 'web');
      expect(probe.processors, 0);
      expect(probe.environment('PATH'), isNull);
      expect(probe.readFile('/'), isNull);
      expect(probe.property('ro.hardware'), '');
      expect(probe.sysctlString('hw.machine'), isNull);
      expect(probe.sysctlInt('hw.ncpu'), isNull);
      expect(AudDeviceClass.fromProbe(probe).platform, 'web');
    });
  });
}
