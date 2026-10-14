// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'aud_device_class.dart';

/// The probe where the system cannot be read (web): an empty device.
AudDeviceProbe createProbe() => const AudDeviceProbeStub();

// #############################################################################
/// A probe that reads nothing: the web knows no cores and no model.
class AudDeviceProbeStub implements AudDeviceProbe {
  /// Creates the probe.
  const AudDeviceProbeStub();

  @override
  String get os => 'web';

  @override
  int get processors => 0;

  @override
  String? environment(String name) => null;

  @override
  String? readFile(String path) => null;

  @override
  String property(String name) => '';

  @override
  String? sysctlString(String name) => null;

  @override
  int? sysctlInt(String name) => null;
}
