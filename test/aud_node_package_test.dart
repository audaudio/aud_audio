// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
import 'package:aud_audio/aud_audio.dart';
import 'package:test/test.dart';

void main() {
  group('AudPackageRegistration', () {
    test('names the result of the register function', () {
      const ok = AudPackageRegistration('a', AUD_OK);
      expect(ok.isRegistered, isTrue);
      expect(ok.result, 'AUD_OK');
      const refused = AudPackageRegistration('b', AUD_ERROR_ABI_MAJOR);
      expect(refused.isRegistered, isFalse);
      expect(
        refused.toString(),
        'AudPackageRegistration(b, AUD_ERROR_ABI_MAJOR)',
      );
    });
  });
}
