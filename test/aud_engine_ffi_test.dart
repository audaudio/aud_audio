// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:test/test.dart';

import 'aud_test_nodes.dart';

void main() {
  const timeout = Duration(seconds: 5);

  AudEngineFfi open({
    double sampleRate = 0,
    List<AudNodePackage> packages = const [],
  }) {
    final engine = AudEngineFfi(
      config: AudEngineConfig(
        backend: AudIoBackend.nullDevice,
        outputChannels: 1,
        sampleRate: sampleRate,
        maxFrames: 256,
        manualClock: true,
      ),
      packages: packages,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  /// Builds oscillator -> filter -> output.
  ({AudNode osc, AudNode filter}) build(AudGraph graph) {
    final osc = graph.createNode('aud.graph.oscillator');
    final filter = graph.createNode('aud.graph.filter');
    graph.transaction(
      (tx) => tx
        ..connect(osc, filter)
        ..connect(filter, graph.io),
    );
    graph.setParam(osc, 'frequency', 440);
    graph.setParam(filter, 'cutoff', 2000);
    return (osc: osc, filter: filter);
  }

  /// Plays [frames] in device callbacks of 480 frames on the manual clock.
  Float32List play(AudEngineFfi engine, int frames) {
    final rate = engine.format.sampleRate;
    final out = Float32List(frames);
    var host = AudClock.nowNs();
    for (var done = 0; done < frames; done += 480) {
      final n = min(480, frames - done);
      out.setAll(done, engine.stream.debugProcess(frames: n, hostTimeNs: host));
      host += (n * 1e9 / rate).round();
    }
    return out;
  }

  int risingCrossings(Float32List samples) {
    var count = 0;
    for (var i = 1; i < samples.length; i++) {
      if (samples[i - 1] < 0 && samples[i] >= 0) count++;
    }
    return count;
  }

  double peak(Float32List samples) =>
      samples.fold(0, (a, b) => max(a, b.abs()));

  Future<void> reach(AudEngine engine, AudEngineState state) async {
    if (engine.state == state) return;
    await engine.states.firstWhere((s) => s == state).timeout(timeout);
  }

  Future<AudIoNotification> next(
    AudEngineFfi engine,
    AudIoNotificationType type,
  ) => engine.stream.notifications
      .firstWhere((n) => n.type == type)
      .timeout(timeout);

  group('AudEngineFfi', () {
    group('renders oscillator -> filter -> output', () {
      for (final rate in [48000.0, 44100.0]) {
        test('at ${rate.round()} Hz like the offline renderer', () {
          final engine = open(sampleRate: rate);
          expect(engine.state, AudEngineState.created);
          build(engine.graph);
          engine.start();
          expect(engine.state, AudEngineState.running);
          expect(engine.format.sampleRate, rate);
          expect(engine.graph.sampleRate, rate);
          final live = play(engine, rate.round());
          expect(risingCrossings(live), inInclusiveRange(439, 441));

          // The same graph rendered offline in the same blocks.
          final reference = AudGraphFfi(
            maxFrames: 256,
            outputChannels: const [1],
            listen: false,
          );
          addTearDown(reference.dispose);
          build(reference);
          reference.prepare(sampleRate: rate, maxFrames: 256);
          reference.start();
          final offline = AudOfflineRenderer(
            reference,
          ).render(frames: live.length, blockFrames: 240).single.single;
          for (var i = 0; i < live.length; i += 97) {
            expect(live[i], closeTo(offline[i], 1e-4), reason: 'frame $i');
          }
          expect(engine.stats.blocksRendered, greaterThan(0));
          expect(engine.counters.renderErrors, 0);
        });
      }
    });

    group('runs one sequence for every change (lifecycle-001)', () {
      test(
        'a new sample rate: suspend, prepare, resume, acknowledge',
        () async {
          final engine = open();
          build(engine.graph);
          final states = <AudEngineState>[];
          engine.states.listen(states.add);
          engine.start();
          engine.graph.transport(const AudTransportRequest.start());
          play(engine, 4800);
          final beat = engine.graph.transportState.beat;
          expect(beat, greaterThan(0));

          final changed = next(engine, AudIoNotificationType.formatChanged);
          engine.session.inject(AudIoFault.sampleRate, 44100);
          await changed;
          await Future<void>.delayed(Duration.zero);
          expect(states, [
            AudEngineState.prepared,
            AudEngineState.running,
            AudEngineState.suspended,
            AudEngineState.running,
          ]);
          await _waitFor(() => engine.stream.state == AudIoState.running);
          final after = play(engine, 44100);
          expect(engine.graph.sampleRate, 44100);
          expect(risingCrossings(after), inInclusiveRange(439, 441));
          // The transport and the nodes survived.
          expect(engine.graph.transportState.beat, greaterThan(beat));
          expect(engine.graph.nodes, hasLength(2));
          expect(engine.counters.renderErrors, 0);
        },
      );

      for (final (fault, value) in [
        (AudIoFault.disconnect, 0),
        (AudIoFault.route, 0),
      ]) {
        test('${fault.name}: the graph plays on after it', () async {
          final engine = open();
          build(engine.graph);
          engine.start();
          play(engine, 4800);
          final suspended = <AudEngineState>[];
          engine.states.listen(suspended.add);
          engine.session.inject(fault, value);
          await _waitFor(
            () =>
                suspended.contains(AudEngineState.running) &&
                engine.stream.state == AudIoState.running,
          );
          expect(engine.state, AudEngineState.running);
          expect(peak(play(engine, 4800)), greaterThan(0.1));
        });
      }

      test('a failing start recovers once the device runs', () async {
        final engine = open();
        build(engine.graph);
        engine.start();
        play(engine, 480);
        engine.session.inject(AudIoFault.failStart, 1);
        engine.session.inject(AudIoFault.disconnect);
        await reach(engine, AudEngineState.suspended);
        await _waitFor(() => engine.stream.state == AudIoState.running);
        await reach(engine, AudEngineState.running);
        expect(peak(play(engine, 4800)), greaterThan(0.1));
        expect(engine.counters.recoveries, greaterThan(0));
      });

      test('an interruption suspends, its end resumes', () async {
        final engine = open();
        build(engine.graph);
        engine.start();
        engine.graph.transport(const AudTransportRequest.start());
        play(engine, 4800);
        final beat = engine.graph.transportState.beat;
        engine.session.interrupt();
        await reach(engine, AudEngineState.suspended);
        expect(engine.graph.state, AudGraphState.suspended);
        engine.session.resume();
        await reach(engine, AudEngineState.running);
        await _waitFor(() => engine.stream.state == AudIoState.running);
        expect(peak(play(engine, 4800)), greaterThan(0.1));
        expect(engine.graph.transportState.beat, greaterThan(beat));
      });

      test('a change while prepared prepares again', () async {
        final engine = open();
        engine.prepare();
        final changed = next(engine, AudIoNotificationType.formatChanged);
        engine.session.inject(AudIoFault.sampleRate, 44100);
        await changed;
        await Future<void>.delayed(Duration.zero);
        expect(engine.state, AudEngineState.prepared);
        expect(engine.graph.sampleRate, 44100);
      });

      test('a change while stopped waits for the next start', () async {
        final engine = open();
        engine.start();
        engine.stop();
        engine.session.inject(AudIoFault.sampleRate, 44100);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(engine.state, AudEngineState.stopped);
        engine.start();
        expect(engine.graph.sampleRate, 44100);
      });
    });

    group('after the code review', () {
      test('start() restarts a stream whose recovery failed', () async {
        final engine = AudEngineFfi(
          config: const AudEngineConfig(
            backend: AudIoBackend.nullDevice,
            outputChannels: 1,
            maxFrames: 256,
            manualClock: true,
            recoveryTimeout: Duration(milliseconds: 30),
          ),
        );
        addTearDown(engine.dispose);
        build(engine.graph);
        engine.start();
        engine.session.inject(AudIoFault.failOpen, 1000);
        engine.session.inject(AudIoFault.disconnect);
        await _waitFor(() => engine.stream.state == AudIoState.failed);
        expect(engine.state, AudEngineState.suspended);
        engine.session.inject(AudIoFault.failOpen, 0);
        engine.start();
        await _waitFor(() => engine.stream.state == AudIoState.running);
        expect(engine.state, AudEngineState.running);
        expect(peak(play(engine, 4800)), greaterThan(0.1));
      });

      test('a failing open releases the session and the graph', () {
        // The graph refuses 1000 channels; the stream refuses 64.
        for (final (channels, error) in [
          (1000, isA<AudGraphException>()),
          (64, isA<AudIoException>()),
        ]) {
          expect(
            () => AudEngineFfi(
              config: AudEngineConfig(
                backend: AudIoBackend.nullDevice,
                outputChannels: channels,
                manualClock: true,
              ),
            ),
            throwsA(error),
          );
        }
      });

      test('pump() takes the notifications without listening', () async {
        final engine = AudEngineFfi(
          config: const AudEngineConfig(
            backend: AudIoBackend.nullDevice,
            outputChannels: 1,
            manualClock: true,
            listen: false,
          ),
        );
        addTearDown(engine.dispose);
        engine.start();
        engine.session.inject(AudIoFault.sampleRate, 44100);
        await _waitFor(() {
          engine.pump();
          return engine.graph.sampleRate == 44100;
        });
        expect(engine.state, AudEngineState.running);
      });

      test('the route is read once and again after a change', () async {
        final engine = open();
        expect(engine.route, AudIoRoute.virtual);
        expect(engine.route, AudIoRoute.virtual);
        engine.start();
        engine.session.inject(AudIoFault.route);
        await _waitFor(() => engine.stream.state == AudIoState.running);
        expect(engine.route, AudIoRoute.virtual);
      });

      test('presentationTimeNs() without a callback is its host time', () {
        final engine = open();
        expect(AudEngineFfi.presentationTimeNs(480, engine.counters), 0);
      });
    });

    group('shuts down in reverse', () {
      for (final from in [
        AudEngineState.created,
        AudEngineState.prepared,
        AudEngineState.running,
        AudEngineState.suspended,
        AudEngineState.stopped,
      ]) {
        test('from ${from.name}', () async {
          final engine = open();
          final states = <AudEngineState>[];
          if (from != AudEngineState.created) engine.prepare();
          if (from == AudEngineState.running ||
              from == AudEngineState.suspended ||
              from == AudEngineState.stopped) {
            engine.start();
          }
          if (from == AudEngineState.suspended) {
            engine.session.interrupt();
            await reach(engine, AudEngineState.suspended);
          }
          if (from == AudEngineState.stopped) engine.stop();
          expect(engine.state, from);
          engine.states.listen(states.add);
          engine.dispose();
          await Future<void>.delayed(Duration.zero);
          final wasRunning =
              from == AudEngineState.running ||
              from == AudEngineState.suspended;
          expect(states, [
            if (wasRunning) AudEngineState.stopped,
            AudEngineState.disposed,
          ]);
          expect(engine.stream.isClosed, isTrue);
          expect(engine.graph.isDisposed, isTrue);
          expect(engine.session.isDisposed, isTrue);
          engine.dispose();
          expect(engine.prepare, throwsStateError);
          expect(engine.start, throwsStateError);
          expect(engine.stop, throwsStateError);
          expect(engine.measureCommandToSound, throwsStateError);
        });
      }

      test('start and stop are idempotent; prepare twice is refused', () {
        final engine = open();
        engine.stop();
        expect(engine.state, AudEngineState.created);
        engine.start();
        engine.start();
        expect(engine.state, AudEngineState.running);
        expect(engine.prepare, throwsStateError);
        engine.stop();
        engine.stop();
        expect(engine.state, AudEngineState.stopped);
        engine.start();
        expect(engine.state, AudEngineState.running);
      });
    });

    group('registers node packages (abi-001)', () {
      test('a package of the same ABI registers its node types', () {
        final engine = open(packages: [AudTestNodes.current]);
        expect(engine.registrations, isEmpty);
        engine.prepare();
        expect(engine.registrations.single.isRegistered, isTrue);
        expect(engine.registrations.single.result, 'AUD_OK');
        expect(
          engine.nodeTypes.map((t) => t.typeId),
          containsAll(['aud.graph.oscillator', 'aud.test.invert']),
        );

        // The node of the package renders: the inverted oscillator.
        final osc = engine.graph.createNode('aud.graph.oscillator');
        final invert = engine.graph.createNode('aud.test.invert');
        engine.graph.transaction(
          (tx) => tx
            ..connect(osc, invert)
            ..connect(invert, engine.graph.io),
        );
        engine.start();
        final out = play(engine, 4800);
        expect(peak(out), greaterThan(0.1));
      });

      test('a package of another ABI major is refused', () {
        final engine = open(
          packages: [AudTestNodes.future, const _WebPackage()],
        );
        engine.start();
        expect(engine.registrations.first.isRegistered, isFalse);
        expect(engine.registrations.first.result, 'AUD_ERROR_ABI_MAJOR');
        expect(engine.registrations.last.result, 'AUD_ERROR_UNSUPPORTED');
        expect(
          engine.nodeTypes.map((t) => t.typeId),
          isNot(contains('aud.test.invert')),
        );
        expect(engine.report(), contains('aud_test_nodes_future'));
      });
    });

    group('numbers', () {
      test('measures command-to-sound to the presentation time', () async {
        final engine = open();
        build(engine.graph);
        engine.start();
        // A device callback of 480 frames every 10 ms, whose first frame
        // reaches the output 20 ms after the callback starts.
        final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
          engine.stream.debugProcess(
            frames: 480,
            hostTimeNs: AudClock.nowNs() + 20000000,
          );
        });
        addTearDown(timer.cancel);
        for (var i = 0; i < 3; i++) {
          final latency = await engine.measureCommandToSound();
          expect(latency, inInclusiveRange(10000000, 200000000));
        }
        timer.cancel();
        final numbers = engine.numbers;
        expect(numbers.commandToSoundNs, hasLength(3));
        expect(numbers.blocksRendered, greaterThan(0));
        expect(numbers.renderTimeMaxNs, greaterThan(0));
        expect(numbers.callbacks, greaterThan(0));
        expect(numbers.xruns, 0);
        final report = engine.report();
        expect(report, contains('state: running'));
        expect(report, contains('route: '));
        expect(report, contains('commandToSoundMeanNs'));
      });

      test('measures only while running', () {
        final engine = open();
        expect(engine.measureCommandToSound, throwsStateError);
      });

      test('presentationTimeNs() moves the last callback by the frames', () {
        final engine = open();
        engine.start();
        engine.stream.debugProcess(frames: 480, hostTimeNs: 1000000000);
        final time = engine.counters.lastTime;
        expect(
          AudEngineFfi.presentationTimeNs(
            time.samplePosition + 480,
            engine.counters,
          ),
          time.hostTimeNs + 10000000,
        );
      });

      test('numbers before any block', () {
        final engine = open();
        expect(engine.numbers.renderTimeMeanNs, 0);
        expect(engine.route, AudIoRoute.virtual);
      });
    });
  });
}

class _WebPackage implements AudNodePackage {
  const _WebPackage();

  @override
  String get name => 'web_only';
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
