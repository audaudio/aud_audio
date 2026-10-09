// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'dart:ffi';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:aud_test_nodes/aud_test_nodes.dart';
import 'package:test/test.dart';

void main() {
  group('AudNativeNodePackage', () {
    test('registerWith(host) calls the register function', () {
      final graph = AudGraphFfi(listen: false);
      addTearDown(graph.dispose);
      final package = AudNativeNodePackage(
        'aud_test_nodes',
        Native.addressOf(aud_test_nodes_register),
      );
      expect(package.name, 'aud_test_nodes');
      expect(package.registerWith(graph.hostApi), AUD_OK);
      expect(package.registerWith(graph.hostApi), AUD_ERROR_DUPLICATE_TYPE);
      expect(graph.nodeType('aud.test.invert'), isNotNull);
    });
  });
}
