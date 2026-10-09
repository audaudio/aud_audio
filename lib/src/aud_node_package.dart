// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio_core/aud_audio_core.dart';

// #############################################################################
/// A DSP package whose node types the engine registers at its start: on
/// native platforms an `AudNativeNodePackage` with the package's
/// `aud_<package>_register(const AudHostApi*)` function.
abstract interface class AudNodePackage {
  /// The name of the package, e.g. `aud_dsp_effects`.
  String get name;
}

// #############################################################################
/// The outcome of registering an [AudNodePackage].
class AudPackageRegistration {
  /// The registration of [package] with the result [code].
  const AudPackageRegistration(this.package, this.code);

  /// The package.
  final String package;

  /// The result code of the register function, `AUD_OK` on success.
  final int code;

  /// Whether the node types of the package are registered.
  bool get isRegistered => code == AUD_OK;

  /// The name of [code], e.g. `AUD_ERROR_ABI_MAJOR` for a package built
  /// against another major of the ABI (abi-001).
  String get result => AudAbi.resultName(code);

  @override
  String toString() => 'AudPackageRegistration($package, $result)';
}
