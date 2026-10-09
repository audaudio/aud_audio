// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
// Runs the example on a simulator, an emulator or a device:
//
//   flutter test integration_test/engine_test.dart -d <device>
//
// On a real device it prints the numbers of the engine; AUD_MEASURE_SECONDS
// (--dart-define) sets how long the engine plays before the report, e.g.
// 600 for the xruns over 10 minutes of S24 and io-001/io-002.

// ignore_for_file: avoid_print

import 'package:aud_audio/aud_audio.dart';
import 'package:aud_audio_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _seconds = int.fromEnvironment('AUD_MEASURE_SECONDS', defaultValue: 3);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays oscillator -> filter and measures the engine', (
    tester,
  ) async {
    await tester.pumpWidget(const EngineApp());
    final page = tester.state<EnginePageState>(find.byType(EnginePage));
    final engine = page.engine;
    expect(engine.state, AudEngineState.created);

    await tester.tap(find.byKey(const Key('toggle')));
    await tester.pump();
    expect(engine.state, AudEngineState.running);
    expect(find.text('Stop'), findsOneWidget);

    // Frequency and cutoff go to the graph.
    await tester.drag(find.byKey(const Key('frequency')), const Offset(80, 0));
    await tester.drag(find.byKey(const Key('cutoff')), const Offset(-80, 0));
    await tester.pump();

    await tester.runAsync(
      () => Future<void>.delayed(Duration(seconds: _seconds)),
    );
    await tester.runAsync(() => page.measure(count: 50));
    await tester.pump();

    final numbers = engine.numbers;
    expect(numbers.callbacks, greaterThan(0));
    expect(numbers.blocksRendered, greaterThan(0));
    expect(numbers.commandToSoundNs, hasLength(50));
    expect(engine.counters.renderErrors, 0);
    print(engine.report());

    await tester.tap(find.byKey(const Key('copy')));
    await tester.pump();
    expect(find.text('Report copied'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle')));
    await tester.pump();
    expect(engine.state, AudEngineState.stopped);
  });
}
