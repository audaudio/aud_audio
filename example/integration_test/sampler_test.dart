// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
// Runs the sampler page (ticket 25) on a simulator, an emulator or a device
// and prints the numbers of the M1 budgets (ticket 17, Verification):
//
//   flutter test integration_test/sampler_test.dart -d <device> \
//     --dart-define=AUD_MEASURE_SECONDS=600
//
// - the load of the instrument, at most 2 s within the cache budget;
// - 64 voices at 48 kHz in blocks of 128 frames, rendered offline on the
//   device at the live quality: at most 50 % of a block (2.67 ms); and
//   live at the buffer the device grants;
// - command to sound: at most a block plus the output latency;
// - xruns while the auto-play plays with an animated UI for
//   AUD_MEASURE_SECONDS (600 for the ten minutes on the reference device).
//
// AUD_ASSERT_BUDGETS=true turns the budgets into expectations; without it
// the test prints them, since a simulator or an emulator runs at the speed
// of its host.

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:aud_audio_example/main.dart';
import 'package:aud_audio_example/sampler_page.dart';
import 'package:aud_dsp_sampler/aud_dsp_sampler_ffi.dart';
import 'package:aud_dsp_sampler/testing.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _seconds = int.fromEnvironment('AUD_MEASURE_SECONDS', defaultValue: 5);
const _assertBudgets = bool.fromEnvironment('AUD_ASSERT_BUDGETS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads, plays 64 voices and auto-plays with the numbers', (
    tester,
  ) async {
    await tester.pumpWidget(const EngineApp());
    await tester.tap(find.byKey(const Key('page-sampler')));
    await tester.pump();
    final page = tester.state<SamplerPageState>(find.byType(SamplerPage));
    final engine = page.engine;

    // The instrument is written and loaded.
    await _until(tester, () => page.load != null && !page.load!.isRunning);
    final load = page.load!;
    expect(load.succeeded, isTrue, reason: load.message);
    final loadMs = load.duration!.inMicroseconds / 1000;
    print('load of the test instrument: $loadMs ms');
    if (_assertBudgets) expect(loadMs, lessThanOrEqualTo(2000));

    // A key of the keyboard sounds.
    await tester.tap(find.byKey(const Key('sampler-toggle')));
    await tester.pump();
    expect(engine.state, AudEngineState.running);
    await tester.ensureVisible(find.byKey(const Key('keyboard')));
    await tester.pumpAndSettle();
    // A finger holds a key; a tap would be a note of no length.
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('keyboard'))),
    );
    await _until(tester, () => engine.stats.outputPeak > 0);
    await _until(tester, () => page.voices == 1);
    await finger.up();

    // Another instrument swaps in while it plays.
    final swap = await tester.runAsync(() => page.selectInstrument(2));
    expect(swap!.succeeded, isTrue, reason: swap.message);
    print('load of Mellow: ${swap.duration!.inMilliseconds} ms');

    // 64 voices live, at the buffer the device grants.
    engine.graph.resetStats();
    page.playVoices(64);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    await _until(tester, () => page.voices == 64);
    final live = engine.numbers;
    final format = engine.format;
    // The graph renders the blocks of the device's callbacks.
    final blockFrames = format.bufferFrames > 0
        ? format.bufferFrames
        : format.maxFrames;
    final blockNs = blockFrames / format.sampleRate * 1e9;
    print(
      '64 voices live: block $blockFrames frames '
      '(${(blockNs / 1e6).toStringAsFixed(2)} ms), render max '
      '${live.renderTimeMaxNs / 1e6} ms '
      '(${(100 * live.renderTimeMaxNs / blockNs).toStringAsFixed(0)} %), '
      'mean ${live.renderTimeMeanNs / 1e6} ms '
      '(${(100 * live.renderTimeMeanNs / blockNs).toStringAsFixed(0)} %)',
    );
    if (_assertBudgets) {
      expect(live.renderTimeMaxNs, lessThanOrEqualTo(blockNs / 2));
    }
    page.releaseVoices();
    await tester.pump();

    // Command to sound through the same queue as the notes.
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await engine.measureCommandToSound();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final latency = engine.numbers;
    print(
      'command to sound: mean ${latency.commandToSoundMeanNs! / 1e6} ms, '
      'max ${latency.commandToSoundMaxNs! / 1e6} ms, output latency '
      '${latency.outputLatencyFrames} frames',
    );

    // The auto-play with the animated UI; no xrun.
    engine.graph.resetStats();
    final xrunsBefore = engine.numbers.xruns;
    page.startAutoPlay();
    final end = DateTime.now().add(Duration(seconds: _seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
    }
    page.stopAutoPlay();
    await tester.pump();
    final played = engine.numbers;
    final xruns = played.xruns - xrunsBefore;
    print(
      'auto-play for $_seconds s: xruns $xruns, render max '
      '${played.renderTimeMaxNs / 1e6} ms, mean '
      '${played.renderTimeMeanNs / 1e6} ms, late ${played.lateCallbacks}',
    );
    if (_assertBudgets) expect(xruns, 0);
    expect(engine.counters.renderErrors, 0);
    print(engine.report());

    await tester.tap(find.byKey(const Key('sampler-toggle')));
    await tester.pump();
    expect(engine.state, AudEngineState.stopped);
  });

  testWidgets('renders 64 voices offline in blocks of 128 frames', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final instrument = AudSfzTestInstrument.write(
      '${directory.path}/aud_offline_instrument',
    );
    final graph = AudGraphFfi(maxFrames: 128, listen: false);
    addTearDown(graph.dispose);
    AudDspSampler.registerWith(graph.hostApi);
    final node = graph.createNode(
      AudSfzSampler.typeId,
      preset: instrument.preset(),
    );
    graph.transaction((tx) => tx.connect(node, graph.io));
    graph.start();
    expect(graph.waitLoads(timeout: const Duration(seconds: 10)), isTrue);
    // An offline render uses sfizz's best quality; the budget is the live
    // one, so the render takes the live quality.
    graph.sendMessage(node, AudOscMessage('/freewheeling_sample_quality', [2]));
    graph.sendMessage(
      node,
      AudOscMessage('/freewheeling_oscillator_quality', [1]),
    );
    final renderer = AudOfflineRenderer(graph);
    renderer.render(frames: 128);
    for (var note = 30; note < 94; note++) {
      for (final event in AudUmpEvent.fromMessage(
        MidiNoteOn(channel: 0, note: note, velocity: 100),
      )) {
        graph.sendEvent(node, event);
      }
    }
    // The notes start and stream; then 2 s are measured in the graph's
    // statistics, which time each block inside the render.
    renderer.render(frames: 48000, blockFrames: 128);
    graph.resetStats();
    final watch = Stopwatch()..start();
    renderer.render(frames: 96000, blockFrames: 128);
    final wall = watch.elapsedMicroseconds;
    final stats = graph.stats;
    final mean = stats.renderTimeSumNs / stats.blocksRendered / 1000;
    final result = {
      'blocks': stats.blocksRendered,
      'meanUs': mean.round(),
      'maxUs': (stats.renderTimeMaxNs / 1000).round(),
      'wallPerBlockUs': (wall / stats.blocksRendered).round(),
      'budgetUs': 1333,
    };
    print('64 voices offline at 128 frames: ${jsonEncode(result)}');
    if (_assertBudgets) expect(mean, lessThanOrEqualTo(1333));
  });
}

// Pumps until [condition] holds, at most 15 s.
Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
