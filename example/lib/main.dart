// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:math';

import 'package:aud_audio/aud_audio_ffi.dart';
import 'package:aud_dsp_sampler/aud_dsp_sampler_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sampler_page.dart';

void main() => runApp(const EngineApp());

// #############################################################################
/// The example of the Audanika Audio Engine on one engine with two pages:
/// oscillator -> filter -> output on the reference nodes of the graph, and
/// the SFZ sampler of `aud_dsp_sampler` with a keyboard (ticket 25); each
/// with the numbers of the engine.
class EngineApp extends StatefulWidget {
  /// Creates the app; [config] replaces the engine's configuration (tests).
  const EngineApp({super.key, this.config = const AudEngineConfig()});

  /// The configuration of the engine.
  final AudEngineConfig config;

  @override
  State<EngineApp> createState() => EngineAppState();
}

// #############################################################################
/// The state of [EngineApp]: the engine both pages play on; public for the
/// integration tests.
class EngineAppState extends State<EngineApp> {
  /// The engine, with the sampler registered.
  late final AudEngine engine = AudEngine(
    config: widget.config,
    packages: [
      AudNativeNodePackage(AudDspSampler.name, AudDspSampler.register),
    ],
  );

  /// The page on screen: 0 the oscillator, 1 the sampler.
  int page = 0;

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  /// Shows the page [index].
  void showPage(int index) => setState(() => page = index);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'aud_audio',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(
        title: Text(page == 0 ? 'aud_audio engine' : 'aud_audio sampler'),
      ),
      // Only the page on screen is built: it creates its nodes and removes
      // them when it goes.
      body: page == 0
          ? EnginePage(engine: engine)
          : SamplerPage(engine: engine),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: showPage,
        destinations: const [
          NavigationDestination(
            key: Key('page-oscillator'),
            icon: Icon(Icons.graphic_eq),
            label: 'Oscillator',
          ),
          NavigationDestination(
            key: Key('page-sampler'),
            icon: Icon(Icons.piano),
            label: 'Sampler',
          ),
        ],
      ),
    ),
  );
}

// #############################################################################
/// The page with the oscillator, its controls and the numbers.
class EnginePage extends StatefulWidget {
  /// Creates the page on [engine].
  const EnginePage({super.key, required this.engine});

  /// The engine.
  final AudEngine engine;

  @override
  State<EnginePage> createState() => EnginePageState();
}

// #############################################################################
/// The state of [EnginePage]; public for the integration tests.
class EnginePageState extends State<EnginePage> {
  /// The engine.
  AudEngine get engine => widget.engine;

  late final AudNode _osc;
  late final AudNode _filter;
  late final StreamSubscription<AudEngineState> _states;
  Timer? _refresh;
  double _frequency = 220;
  double _cutoff = 2000;
  bool _measuring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final graph = engine.graph;
    _osc = graph.createNode('aud.graph.oscillator');
    _filter = graph.createNode('aud.graph.filter');
    graph.transaction(
      (tx) => tx
        ..connect(_osc, _filter)
        ..connect(_filter, graph.io),
    );
    graph.setParam(_osc, 'frequency', _frequency);
    graph.setParam(_osc, 'amplitude', 0.3);
    graph.setParam(_filter, 'cutoff', _cutoff);
    _states = engine.states.listen((_) => setState(() {}));
    _refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    unawaited(_states.cancel());
    if (!engine.graph.isDisposed) {
      engine.graph.transaction(
        (tx) => tx
          ..remove(_osc)
          ..remove(_filter),
      );
    }
    super.dispose();
  }

  // ...........................................................................
  /// Starts or stops the engine.
  void toggle() => setState(() {
    if (engine.state == AudEngineState.running ||
        engine.state == AudEngineState.suspended) {
      engine.stop();
    } else {
      engine.start();
    }
  });

  /// Sets the frequency of the oscillator in Hz.
  void setFrequency(double hz) {
    _frequency = hz;
    engine.graph.setParam(_osc, 'frequency', hz, rampFrames: 256);
    setState(() {});
  }

  /// Sets the cutoff of the filter in Hz.
  void setCutoff(double hz) {
    _cutoff = hz;
    engine.graph.setParam(_filter, 'cutoff', hz, rampFrames: 256);
    setState(() {});
  }

  /// Measures the command-to-sound latency [count] times.
  Future<void> measure({int count = 20}) async {
    setState(() => _measuring = true);
    try {
      for (var i = 0; i < count; i++) {
        await engine.measureCommandToSound();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      _error = null;
    } on Object catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  /// Copies the report of the engine to the clipboard.
  Future<void> copyReport() async {
    await Clipboard.setData(ClipboardData(text: engine.report()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report copied')));
  }

  // ...........................................................................
  @override
  Widget build(BuildContext context) {
    final state = engine.state;
    final running =
        state == AudEngineState.running || state == AudEngineState.suspended;
    final format = engine.format;
    final numbers = engine.numbers;
    String ms(num? ns) => ns == null ? '-' : (ns / 1e6).toStringAsFixed(2);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'State: ${state.name}',
          key: const Key('state'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('Route: ${engine.route.name}', key: const Key('route')),
        Text(
          'Format: ${format.sampleRate.toStringAsFixed(0)} Hz, '
          '${format.outputChannels} out, buffer ${format.bufferFrames} '
          '(${format.backend})',
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('toggle'),
          onPressed: toggle,
          child: Text(running ? 'Stop' : 'Start'),
        ),
        const SizedBox(height: 16),
        Text('Frequency ${_frequency.round()} Hz'),
        Slider(
          key: const Key('frequency'),
          value: log(_frequency),
          min: log(50),
          max: log(2000),
          onChanged: (v) => setFrequency(exp(v)),
        ),
        Text('Cutoff ${_cutoff.round()} Hz'),
        Slider(
          key: const Key('cutoff'),
          value: log(_cutoff),
          min: log(100),
          max: log(12000),
          onChanged: (v) => setCutoff(exp(v)),
        ),
        const Divider(),
        Text(
          'Render: max ${ms(numbers.renderTimeMaxNs)} ms, '
          'mean ${ms(numbers.renderTimeMeanNs)} ms',
        ),
        Text(
          'Callbacks: ${numbers.callbacks}, xruns ${numbers.xruns}, '
          'late ${numbers.lateCallbacks}',
          key: const Key('callbacks'),
        ),
        Text(
          'Command to sound: min ${ms(numbers.commandToSoundMinNs)} ms, '
          'mean ${ms(numbers.commandToSoundMeanNs)} ms, '
          'max ${ms(numbers.commandToSoundMaxNs)} ms '
          '(${numbers.commandToSoundNs.length})',
          key: const Key('latency'),
        ),
        if (_error != null) Text(_error!, key: const Key('error')),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('measure'),
          onPressed: running && !_measuring ? measure : null,
          child: Text(_measuring ? 'Measuring...' : 'Measure latency'),
        ),
        OutlinedButton(
          key: const Key('copy'),
          onPressed: copyReport,
          child: const Text('Copy report'),
        ),
      ],
    );
  }
}
