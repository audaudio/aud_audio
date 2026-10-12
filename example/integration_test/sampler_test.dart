// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
// Runs the sampler page (ticket 25) on a simulator, an emulator or a device
// and prints the numbers of the M1 budgets (ticket 17, Verification):
//
//   flutter test integration_test/sampler_test.dart -d <device> \
//     --dart-define=AUD_WARMUP_SECONDS=1200 \
//     --dart-define=AUD_MEASURE_SECONDS=600
//
// - the load of the instrument, at most 2 s within the cache budget;
// - 64 voices at 48 kHz in blocks of 128 frames, rendered offline on the
//   device at the live quality: at most 50 % of a block (2.67 ms); and
//   live at the buffer the device grants;
// - command to sound: at most a block plus the output latency;
// - xruns while the auto-play plays with an animated UI: first for
//   AUD_WARMUP_SECONDS (default 0; 1200 for the twenty minutes of warm-up
//   under thermal load), then for AUD_MEASURE_SECONDS (600 for the ten
//   minutes on the reference device). Only the xruns, the late callbacks
//   and the render times of the measured part count.
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

const _warmUpSeconds = int.fromEnvironment('AUD_WARMUP_SECONDS');
const _seconds = int.fromEnvironment('AUD_MEASURE_SECONDS', defaultValue: 5);
const _assertBudgets = bool.fromEnvironment('AUD_ASSERT_BUDGETS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Pumps until [condition] holds, at most 15 s.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('timed out');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  // Pumps the frames of the animated UI for [seconds] while the engine
  // plays.
  Future<void> animate(WidgetTester tester, int seconds) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
    }
  }

  testWidgets('loads, plays 64 voices and auto-plays with the numbers', (
    tester,
  ) async {
    await tester.pumpWidget(const EngineApp());
    await tester.tap(find.byKey(const Key('page-sampler')));
    await tester.pump();
    final page = tester.state<SamplerPageState>(find.byType(SamplerPage));
    final engine = page.engine;

    // The instrument is written and loaded.
    await until(tester, () => page.load != null && !page.load!.isRunning);
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
    await until(tester, () => engine.stats.outputPeak > 0);
    await until(tester, () => page.voices == 1);
    await finger.up();

    // Another instrument swaps in while it plays.
    final swap = await tester.runAsync(() => page.selectInstrument(2));
    expect(swap!.succeeded, isTrue, reason: swap.message);
    print('load of Mellow: ${swap.duration!.inMilliseconds} ms');

    // 64 voices live, at the buffer the device grants: the block in which
    // all of them start, then 2 s of the 64 voices playing.
    engine.graph.resetStats();
    page.playVoices(SamplerPageState.testVoices);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    await until(tester, () => page.voices == SamplerPageState.testVoices);
    final burst = engine.numbers;
    engine.graph.resetStats();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    final live = engine.numbers;
    final format = engine.format;
    // The graph renders the blocks of the device's callbacks.
    final blockFrames = format.bufferFrames > 0
        ? format.bufferFrames
        : format.maxFrames;
    final blockNs = blockFrames / format.sampleRate * 1e9;
    String share(num ns) => '${(100 * ns / blockNs).toStringAsFixed(0)} %';
    print(
      '64 voices live: block $blockFrames frames '
      '(${(blockNs / 1e6).toStringAsFixed(2)} ms), render max '
      '${live.renderTimeMaxNs / 1e6} ms (${share(live.renderTimeMaxNs)}), '
      'mean ${live.renderTimeMeanNs / 1e6} ms (${share(live.renderTimeMeanNs)}); '
      'with the start of the 64 notes max ${burst.renderTimeMaxNs / 1e6} ms '
      '(${share(burst.renderTimeMaxNs)})',
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

    // The auto-play with the animated UI: the warm-up, then the measured
    // part without an xrun; only the measured part counts.
    page.startAutoPlay();
    final start = engine.numbers;
    await animate(tester, _warmUpSeconds);
    engine.graph.resetStats();
    final warm = engine.numbers;
    if (_warmUpSeconds > 0) {
      print(
        'warm-up for $_warmUpSeconds s: xruns ${warm.xruns - start.xruns}, '
        'late ${warm.lateCallbacks - start.lateCallbacks}',
      );
    }
    await animate(tester, _seconds);
    page.stopAutoPlay();
    await tester.pump();
    final played = engine.numbers;
    final xruns = played.xruns - warm.xruns;
    print(
      'auto-play for $_seconds s after a warm-up of $_warmUpSeconds s: '
      'xruns $xruns, render max ${played.renderTimeMaxNs / 1e6} ms, mean '
      '${played.renderTimeMeanNs / 1e6} ms, '
      'late ${played.lateCallbacks - warm.lateCallbacks}',
    );
    if (_assertBudgets) expect(xruns, 0);
    expect(engine.counters.renderErrors, 0);
    print(engine.report());

    // The list scrolled down to the keyboard; the button is at its top.
    await tester.scrollUntilVisible(
      find.byKey(const Key('sampler-toggle')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('sampler-toggle')));
    await tester.pump();
    expect(engine.state, AudEngineState.stopped);
  });

  testWidgets('renders 64 voices offline in blocks of 128 frames', (
    tester,
  ) async {
    // The budget: half of a block of 128 frames at 48 kHz.
    const blockFrames = 128;
    const sampleRate = 48000;
    const budgetUs = blockFrames / sampleRate * 1e6 / 2;
    final directory = await getTemporaryDirectory();
    final instrument = AudSfzTestInstrument.write(
      '${directory.path}/aud_offline_instrument',
    );
    final graph = AudGraphFfi(maxFrames: blockFrames, listen: false);
    addTearDown(graph.dispose);
    AudDspSampler.registerWith(graph.hostApi);
    final node = graph.createNode(
      AudSfzSampler.typeId,
      preset: instrument.preset(),
    );
    graph.transaction((tx) => tx.connect(node, graph.io));
    graph.start();
    expect(graph.waitLoads(timeout: const Duration(seconds: 10)), isTrue);
    // The instrument loaded; an instrument that failed would render
    // silence.
    final loads = graph.loads;
    expect(loads, isNotEmpty);
    expect(
      [for (final load in loads) load.resultName],
      everyElement('AUD_OK'),
      reason: [for (final load in loads) load.message].join('; '),
    );
    // An offline render uses sfizz's best quality; the budget is the live
    // one, so the render takes the live quality.
    graph.sendMessage(node, AudOscMessage('/freewheeling_sample_quality', [2]));
    graph.sendMessage(
      node,
      AudOscMessage('/freewheeling_oscillator_quality', [1]),
    );
    final renderer = AudOfflineRenderer(graph);
    renderer.render(frames: blockFrames);
    // The notes of the 64-voice test of the page.
    const first = SamplerPageState.firstVoiceNote;
    for (var note = first; note < first + SamplerPageState.testVoices; note++) {
      for (final event in AudUmpEvent.fromMessage(
        MidiNoteOn(
          channel: 0,
          note: note,
          velocity: SamplerPageState.voiceVelocity,
        ),
      )) {
        graph.sendEvent(node, event);
      }
    }
    // The notes start and stream; then 2 s are measured in the graph's
    // statistics, which time each block inside the render.
    renderer.render(frames: sampleRate, blockFrames: blockFrames);
    graph.resetStats();
    final watch = Stopwatch()..start();
    renderer.render(frames: 2 * sampleRate, blockFrames: blockFrames);
    final wall = watch.elapsedMicroseconds;
    final stats = graph.stats;

    // All 64 voices sounded: sfizz counts them, the output is not silent.
    final answers = <AudNodeMessage>[];
    graph.messages.listen(answers.add);
    graph.sendMessage(node, AudOscMessage('/num_active_voices'));
    renderer.render(frames: blockFrames);
    graph.pump();
    expect(
      [
        for (final answer in answers)
          if (answer.path == '/num_active_voices') answer.arguments,
      ],
      [
        [SamplerPageState.testVoices],
      ],
    );
    expect(stats.outputPeak, greaterThan(0));

    final mean = stats.renderTimeSumNs / stats.blocksRendered / 1000;
    final result = {
      'blocks': stats.blocksRendered,
      'meanUs': mean.round(),
      'maxUs': (stats.renderTimeMaxNs / 1000).round(),
      'wallPerBlockUs': (wall / stats.blocksRendered).round(),
      'budgetUs': budgetUs.round(),
    };
    print('64 voices offline at 128 frames: ${jsonEncode(result)}');
    if (_assertBudgets) expect(mean, lessThanOrEqualTo(budgetUs));
  });
}
