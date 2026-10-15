// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'aud_device_class_stub.dart'
    if (dart.library.ffi) 'aud_device_class_native.dart'
    as platform_probe;

// #############################################################################
/// What a device offers for rendering audio, read once from the system: the
/// model, the cores and the clock of the fastest ones, Android's media
/// performance class. An `AudLoadGovernor` starts from its [startUnits]
/// until the app learned a budget on the device (ticket 29); [key] names
/// the device for that learned budget.
class AudDeviceClass {
  /// Creates the class of a device.
  const AudDeviceClass({
    this.platform = '',
    this.model = '',
    this.soc = '',
    this.cores = 0,
    this.fastCores = 0,
    this.fastCoreMhz = 0,
    this.mediaPerformanceClass = 0,
    this.sdk = 0,
    this.virtual = false,
  });

  /// The class of this device; an empty class on the web.
  factory AudDeviceClass.current() =>
      AudDeviceClass.fromProbe(platform_probe.createProbe());

  /// The class of the device [probe] reads.
  factory AudDeviceClass.fromProbe(AudDeviceProbe probe) => switch (probe.os) {
    'android' => _android(probe),
    'ios' => _ios(probe),
    _ => AudDeviceClass(platform: probe.os, cores: probe.processors),
  };

  // ...........................................................................
  /// The operating system: `android`, `ios`, `macos`, ...; empty when
  /// unknown.
  final String platform;

  /// The model: `SM-T830` on Android, `iPhone17,2` on iOS.
  final String model;

  /// The system on a chip, e.g. `SM8650` or `msm8998`; empty when unknown.
  final String soc;

  /// The cores of the CPU.
  final int cores;

  /// The cores of the fastest cluster: the performance cores on iOS, the
  /// cores with the highest clock on Android.
  final int fastCores;

  /// The highest clock of a core in MHz; 0 when unknown (iOS).
  final int fastCoreMhz;

  /// Android's media performance class (31 to 35); 0 when the device
  /// declares none.
  final int mediaPerformanceClass;

  /// The API level of Android; 0 elsewhere.
  final int sdk;

  /// Whether the device is a simulator or an emulator.
  final bool virtual;

  // ...........................................................................
  /// The name of the device for a budget learned on it: platform and model.
  String get key =>
      '$platform/${model.isEmpty ? 'unknown' : model}'
      '${virtual ? '/virtual' : ''}';

  /// The units - sampler voices - a governor starts with on this class of
  /// device before it learned better; set by the measurements of ticket 29
  /// and raised with the faster voices and the fast cores of ticket 30
  /// (lifecycle-004): the Galaxy Tab S4 (fast cores at 2.36 GHz) renders 96
  /// voices of the stress test at a mean of 0.44 of its block, the iPhone 16
  /// Pro Max (two performance cores) and the iPad Pro M5 (three) far more
  /// than the stress test asks for.
  int get startUnits {
    if (virtual) return 128;
    switch (platform) {
      case 'ios':
        return fastCores >= 3
            ? 192
            : fastCores >= 2
            ? 128
            : 64;
      case 'android':
        if (mediaPerformanceClass >= 34) return 192;
        if (mediaPerformanceClass >= 33) return 160;
        if (mediaPerformanceClass >= 31) return 128;
        if (fastCoreMhz >= 3000) return 128;
        if (fastCoreMhz >= 2600) return 112;
        if (fastCoreMhz >= 2300) return 96;
        return 48;
      default:
        return 64;
    }
  }

  // ...........................................................................
  /// The class as JSON.
  Map<String, Object> toJson() => {
    'platform': platform,
    'model': model,
    'soc': soc,
    'cores': cores,
    'fastCores': fastCores,
    'fastCoreMhz': fastCoreMhz,
    'mediaPerformanceClass': mediaPerformanceClass,
    'sdk': sdk,
    'virtual': virtual,
    'startUnits': startUnits,
  };

  @override
  String toString() => 'AudDeviceClass(${toJson()})';

  // ######################
  // Private
  // ######################

  static AudDeviceClass _android(AudDeviceProbe probe) {
    final clocks = _maxClocksKhz(probe);
    final fastest = clocks.isEmpty ? 0 : clocks.reduce((a, b) => a > b ? a : b);
    String property(String name) => probe.property(name).trim();
    final hardware = property('ro.hardware');
    final soc = [
      property('ro.soc.model'),
      property('ro.board.platform'),
      hardware,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    return AudDeviceClass(
      platform: 'android',
      model: property('ro.product.model'),
      soc: soc,
      cores: probe.processors,
      fastCores: clocks.where((khz) => khz == fastest).length,
      fastCoreMhz: fastest ~/ 1000,
      mediaPerformanceClass:
          int.tryParse(property('ro.odm.build.media_performance_class')) ?? 0,
      sdk: int.tryParse(property('ro.build.version.sdk')) ?? 0,
      virtual:
          property('ro.kernel.qemu') == '1' ||
          property('ro.boot.qemu') == '1' ||
          hardware == 'ranchu' ||
          hardware == 'goldfish',
    );
  }

  /// The highest clock of each core that tells it, in kHz.
  static List<int> _maxClocksKhz(AudDeviceProbe probe) => [
    for (var core = 0; core < probe.processors; core++)
      int.tryParse(
            probe
                    .readFile(
                      '/sys/devices/system/cpu/cpu$core/cpufreq/cpuinfo_max_freq',
                    )
                    ?.trim() ??
                '',
          ) ??
          0,
  ].where((khz) => khz > 0).toList();

  static AudDeviceClass _ios(AudDeviceProbe probe) {
    final simulated = probe.environment('SIMULATOR_MODEL_IDENTIFIER');
    final machine = probe.sysctlString('hw.machine') ?? '';
    return AudDeviceClass(
      platform: 'ios',
      model: simulated ?? machine,
      cores: probe.sysctlInt('hw.ncpu') ?? probe.processors,
      fastCores: probe.sysctlInt('hw.perflevel0.physicalcpu') ?? 0,
      // The simulator's machine is the Mac's architecture, a device's its
      // model, e.g. iPhone17,2.
      virtual: simulated != null || _hostMachines.contains(machine),
    );
  }

  static const _hostMachines = {'arm64', 'x86_64', 'i386'};
}

// #############################################################################
/// Reads what [AudDeviceClass] needs from the system; tests replace it.
abstract interface class AudDeviceProbe {
  /// The operating system as `Platform.operatingSystem` names it.
  String get os;

  /// The processors the system reports.
  int get processors;

  /// The variable [name] of the environment; null if it is not set.
  String? environment(String name);

  /// The text of the file at [path]; null if it cannot be read.
  String? readFile(String path);

  /// The Android system property [name]; empty if it is not set.
  String property(String name);

  /// The text value of the sysctl [name] (Apple); null if unknown.
  String? sysctlString(String name);

  /// The integer value of the sysctl [name] (Apple); null if unknown.
  int? sysctlInt(String name);
}
