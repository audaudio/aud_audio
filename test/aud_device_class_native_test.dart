// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:aud_audio/src/aud_device_class_native.dart';
import 'package:test/test.dart';

void main() {
  group('AudDeviceProbeNative', () {
    final probe = AudDeviceProbeNative();

    test('reads the system', () {
      expect(probe.os, Platform.operatingSystem);
      expect(probe.processors, Platform.numberOfProcessors);
      expect(probe.environment('PATH'), Platform.environment['PATH']);
      expect(probe.readFile('/no/such/file'), isNull);
      final file = File(
        '${Directory.systemTemp.createTempSync('aud_device').path}/f',
      )..writeAsStringSync('42');
      addTearDown(() => file.parent.deleteSync(recursive: true));
      expect(probe.readFile(file.path), '42');
    });

    test('reads the sysctls of Apple', () {
      if (!Platform.isMacOS) return;
      expect(probe.sysctlString('hw.machine'), isNotEmpty);
      expect(probe.sysctlString('no.such.sysctl'), isNull);
      expect(probe.sysctlInt('hw.ncpu'), Platform.numberOfProcessors);
      expect(probe.sysctlInt('hw.memsize'), greaterThan(1 << 30));
      expect(probe.sysctlInt('no.such.sysctl'), isNull);
    });

    test('reads no system properties outside Android', () {
      expect(probe.property('ro.product.model'), '');
    });
  });
}
