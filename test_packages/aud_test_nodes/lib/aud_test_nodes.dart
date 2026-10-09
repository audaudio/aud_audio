// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// A DSP package built apart from the engine; it proves the node registry
/// of `aud_audio` (ticket 22). Its node type is `aud.test.invert`.
library;

import 'dart:ffi';

import 'package:aud_audio_core/aud_audio_core_bindings.dart';

/// Registers `aud.test.invert`, built against the ABI of the engine.
@Native<AudRegisterFunctionFunction>()
external int aud_test_nodes_register(Pointer<AudHostApi> host);

/// Registers `aud.test.invert` as a package built against the next ABI
/// major would; the engine refuses it.
@Native<AudRegisterFunctionFunction>()
external int aud_test_nodes_future_register(Pointer<AudHostApi> host);
