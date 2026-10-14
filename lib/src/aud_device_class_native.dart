// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'aud_device_class.dart';

/// The probe of the native platforms.
AudDeviceProbe createProbe() => AudDeviceProbeNative();

// #############################################################################
/// Reads the device from the system: files of `/sys`, the system properties
/// of Android (`__system_property_get`) and the sysctls of Apple
/// (`sysctlbyname`), through the C library - no plugin, no platform channel.
class AudDeviceProbeNative implements AudDeviceProbe {
  /// Creates the probe.
  AudDeviceProbeNative();

  @override
  String get os => Platform.operatingSystem;

  @override
  int get processors => Platform.numberOfProcessors;

  @override
  String? environment(String name) => Platform.environment[name];

  @override
  String? readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  String property(String name) {
    // coverage:ignore-start
    if (!Platform.isAndroid) return '';
    return using((arena) {
      final value = arena<Uint8>(_propValueMax).cast<Utf8>();
      final length = _propertyGet(name.toNativeUtf8(allocator: arena), value);
      return length > 0 ? value.toDartString(length: length) : '';
    });
    // coverage:ignore-end
  }

  @override
  String? sysctlString(String name) {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    return using((arena) {
      final size = arena<Size>();
      final key = name.toNativeUtf8(allocator: arena);
      if (_sysctl(key, nullptr, size, nullptr, 0) != 0 || size.value == 0) {
        return null;
      }
      // One zeroed byte more: terminated even without a NUL in the value.
      final value = arena<Uint8>(size.value + 1);
      if (_sysctl(key, value.cast(), size, nullptr, 0) != 0) return null;
      return value.cast<Utf8>().toDartString();
    });
  }

  @override
  int? sysctlInt(String name) {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    return using((arena) {
      final size = arena<Size>()..value = sizeOf<Int64>();
      final value = arena<Int64>()..value = 0;
      final key = name.toNativeUtf8(allocator: arena);
      if (_sysctl(key, value.cast(), size, nullptr, 0) != 0) return null;
      return size.value == sizeOf<Int32>()
          ? value.cast<Int32>().value
          : value.value;
    });
  }

  /// PROP_VALUE_MAX of `<sys/system_properties.h>`.
  static const _propValueMax = 92;

  // coverage:ignore-start
  static final _propertyGet = DynamicLibrary.open('libc.so')
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('__system_property_get');
  // coverage:ignore-end

  static final _sysctl = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Void>,
          Size,
        ),
        int Function(
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Void>,
          int,
        )
      >('sysctlbyname');
}
