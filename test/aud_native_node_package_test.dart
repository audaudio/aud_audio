// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:test/test.dart';

import 'aud_test_nodes.dart';

void main() {
  group('AudNativeNodePackage', () {
    test('registerWith(host) calls the register function', () {
      final graph = AudGraphFfi(listen: false);
      addTearDown(graph.dispose);
      final package = AudTestNodes.current;
      expect(package.name, 'aud_test_nodes');
      expect(package.registerWith(graph.hostApi), AUD_OK);
      expect(package.registerWith(graph.hostApi), AUD_ERROR_DUPLICATE_TYPE);
      expect(graph.nodeType('aud.test.invert'), isNotNull);
    });
  });
}
