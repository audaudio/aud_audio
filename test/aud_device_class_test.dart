// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudDeviceClass', () {
    group('fromProbe', () {
      test('reads a Galaxy Tab S4: clusters, SoC, no performance class', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(
            os: 'android',
            processors: 8,
            files: {
              for (var core = 0; core < 4; core++)
                '/sys/devices/system/cpu/cpu$core/cpufreq/cpuinfo_max_freq':
                    '1900800\n',
              for (var core = 4; core < 8; core++)
                '/sys/devices/system/cpu/cpu$core/cpufreq/cpuinfo_max_freq':
                    '2361600\n',
            },
            properties: {
              'ro.product.model': 'SM-T830',
              'ro.board.platform': 'msm8998',
              'ro.hardware': 'qcom',
              'ro.build.version.sdk': '29',
            },
          ),
        );
        expect(device.platform, 'android');
        expect(device.model, 'SM-T830');
        expect(device.soc, 'msm8998');
        expect(device.cores, 8);
        expect(device.fastCores, 4);
        expect(device.fastCoreMhz, 2361);
        expect(device.mediaPerformanceClass, 0);
        expect(device.sdk, 29);
        expect(device.virtual, isFalse);
        expect(device.key, 'android/SM-T830');
        expect(device.startUnits, 32);
      });

      test('prefers the SoC model and reads the performance class', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(
            os: 'android',
            processors: 8,
            files: {
              '/sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_max_freq':
                  '3302400',
            },
            properties: {
              'ro.product.model': 'SM-S928B',
              'ro.soc.model': 'SM8650',
              'ro.board.platform': 'pineapple',
              'ro.odm.build.media_performance_class': '34',
            },
          ),
        );
        expect(device.soc, 'SM8650');
        expect(device.fastCores, 1);
        expect(device.fastCoreMhz, 3302);
        expect(device.mediaPerformanceClass, 34);
        expect(device.startUnits, 96);
      });

      test('knows the emulator', () {
        for (final property in [
          {'ro.kernel.qemu': '1'},
          {'ro.boot.qemu': '1'},
          {'ro.hardware': 'ranchu'},
          {'ro.hardware': 'goldfish'},
        ]) {
          final device = AudDeviceClass.fromProbe(
            _Probe(os: 'android', processors: 4, properties: property),
          );
          expect(device.virtual, isTrue, reason: '$property');
          expect(device.key, 'android/unknown/virtual');
          expect(device.startUnits, 64);
        }
      });

      test('reads an iPhone from its sysctls', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(
            os: 'ios',
            processors: 6,
            sysctls: {
              'hw.machine': 'iPhone17,2',
              'hw.ncpu': 6,
              'hw.perflevel0.physicalcpu': 2,
            },
          ),
        );
        expect(device.model, 'iPhone17,2');
        expect(device.cores, 6);
        expect(device.fastCores, 2);
        expect(device.virtual, isFalse);
        expect(device.key, 'ios/iPhone17,2');
        expect(device.startUnits, 96);
      });

      test('reads the simulated model of the simulator', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(
            os: 'ios',
            processors: 10,
            environment: {'SIMULATOR_MODEL_IDENTIFIER': 'iPhone18,1'},
            sysctls: {'hw.machine': 'arm64'},
          ),
        );
        expect(device.model, 'iPhone18,1');
        expect(device.cores, 10);
        expect(device.fastCores, 0);
        expect(device.virtual, isTrue);
      });

      test('knows the simulator by the architecture of the Mac', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(
            os: 'ios',
            processors: 10,
            sysctls: {'hw.machine': 'arm64', 'hw.perflevel0.physicalcpu': 4},
          ),
        );
        expect(device.model, 'arm64');
        expect(device.virtual, isTrue);
        expect(device.key, 'ios/arm64/virtual');
        expect(device.startUnits, 64);
      });

      test('takes an empty model when iOS tells none', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(os: 'ios', processors: 4),
        );
        expect(device.model, '');
        expect(device.key, 'ios/unknown');
      });

      test('knows only the cores of other systems', () {
        final device = AudDeviceClass.fromProbe(
          _Probe(os: 'linux', processors: 16),
        );
        expect(device.platform, 'linux');
        expect(device.cores, 16);
        expect(device.startUnits, 64);
      });
    });

    group('startUnits', () {
      test('by the performance cores on iOS', () {
        expect(
          const AudDeviceClass(platform: 'ios', fastCores: 4).startUnits,
          128,
        );
        expect(
          const AudDeviceClass(platform: 'ios', fastCores: 2).startUnits,
          96,
        );
        expect(const AudDeviceClass(platform: 'ios').startUnits, 48);
      });

      test('by the performance class and the clock on Android', () {
        int start({int mpc = 0, int mhz = 0}) => AudDeviceClass(
          platform: 'android',
          mediaPerformanceClass: mpc,
          fastCoreMhz: mhz,
        ).startUnits;
        expect(start(mpc: 35), 96);
        expect(start(mpc: 33), 80);
        expect(start(mpc: 31), 64);
        expect(start(mhz: 3200), 64);
        expect(start(mhz: 2800), 48);
        expect(start(mhz: 2400), 32);
        expect(start(), 32);
      });
    });

    test('goes to JSON and a text', () {
      const device = AudDeviceClass(platform: 'ios', model: 'iPad17,3');
      expect(device.toJson()['model'], 'iPad17,3');
      expect(device.toJson()['startUnits'], 48);
      expect(device.toString(), contains('iPad17,3'));
    });

    test('reads this machine', () {
      final device = AudDeviceClass.current();
      expect(device.platform, Platform.operatingSystem);
      expect(device.cores, greaterThan(0));
    });
  });
}

class _Probe implements AudDeviceProbe {
  _Probe({
    required this.os,
    required this.processors,
    this.files = const {},
    this.properties = const {},
    this.sysctls = const {},
    this._environment = const {},
  });

  @override
  final String os;

  @override
  final int processors;

  final Map<String, String> files;
  final Map<String, String> properties;
  final Map<String, Object> sysctls;
  final Map<String, String> _environment;

  @override
  String? environment(String name) => _environment[name];

  @override
  String? readFile(String path) => files[path];

  @override
  String property(String name) => properties[name] ?? '';

  @override
  String? sysctlString(String name) => sysctls[name] as String?;

  @override
  int? sysctlInt(String name) => sysctls[name] as int?;
}
