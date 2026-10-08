// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:aud_audio_graph/aud_audio_graph.dart';
import 'package:aud_audio_io/aud_audio_io.dart';
import 'package:aud_dsp_effects/aud_dsp_effects.dart';
import 'package:aud_dsp_sampler/aud_dsp_sampler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'legacy_sfz.dart';

void main() {
  runApp(const SpikeApp());
}

/// The spike app of ticket 5: a sine from the engine's reference oscillator
/// through the tremolo of `aud_dsp_effects`, the legacy sine sample set
/// through the sfizz sampler of `aud_dsp_sampler`, and the callback and
/// command latency measurements of the stream and the engine.
class SpikeApp extends StatelessWidget {
  /// Creates the app.
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aud_audio spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

/// Which chain the engine renders.
enum Chain { sineTremolo, sampler }

/// The one page of the app.
class SpikePage extends StatefulWidget {
  /// Creates the page.
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  static const double _sampleRate = 48000;
  static const int _lowestKey = 28;
  static const int _highestKey = 108;
  static const String _sampleSet = 'assets/legacy/AUD007869_sineWave.sampleset';

  final AudEngine _engine = AudEngine(sampleRate: _sampleRate, maxFrames: 2048);
  AudIoStream? _stream;
  late final int _sine;
  late final int _tremolo;
  late final int _sampler;
  Chain _chain = Chain.sineTremolo;
  double _frequency = 440;
  double _tremoloRate = 5;
  String _status = 'Loading the legacy sample set ...';
  bool _loaded = false;
  Timer? _statsTimer;
  Timer? _noteTimer;
  int? _playingNote;
  final Stopwatch _sustained = Stopwatch();
  final Random _random = Random();
  AudEngineStats? _engineStats;
  AudIoStats? _ioStats;

  @override
  void initState() {
    super.initState();
    AudDspEffects.register(_engine.hostApi);
    AudDspSampler.register(_engine.hostApi);
    _sine = _engine.createNode('aud.ref.sine');
    _tremolo = _engine.createNode(AudTremolo.typeId);
    _sampler = _engine.createNode(AudSfzSampler.typeId);
    _engine.setParam(_sine, 1, 0.3);
    _engine.setChain([_sine, _tremolo]);
    unawaited(_loadLegacySampleSet());
  }

  // Copies the legacy sample set to the app's support directory and loads
  // it into the sampler as generated SFZ text - before the node enters the
  // chain, as sfizz demands.
  Future<void> _loadLegacySampleSet() async {
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/legacy')
        ..createSync(recursive: true);
      final sampleInfo = await rootBundle.loadString(
        '$_sampleSet/44kHz/sampleInfo.xml',
      );
      final sfz = LegacySfz(
        sampleInfoXml: sampleInfo,
        lowestPitch: _lowestKey,
        highestPitch: _highestKey,
        attackMs: 10,
        releaseMs: 100,
        linearGain: 1.0,
      );
      for (final sample in sfz.samples) {
        final data = await rootBundle.load(
          '$_sampleSet/44kHz/${sample.fileName}',
        );
        File('${directory.path}/${sample.fileName}').writeAsBytesSync(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      _engine.setString(
        _sampler,
        AudSfzSampler.sfzVirtualPath,
        '${directory.path}/legacy.sfz',
      );
      _engine.setString(_sampler, AudSfzSampler.sfzText, sfz.toSfz());
      setState(() {
        _loaded = true;
        _status = 'Legacy sample set loaded: ${sfz.samples.length} samples';
      });
    } catch (error) {
      setState(() => _status = 'Loading failed: $error');
    }
  }

  void _toggleStream() {
    final stream = _stream;
    if (stream == null) {
      try {
        final opened = AudIoStream.open(
          render: AudEngine.renderCallback,
          user: _engine.handle,
          sampleRate: _sampleRate,
        );
        opened.start();
        _stream = opened;
        _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
          setState(() {
            _engineStats = _engine.stats;
            _ioStats = opened.stats;
          });
        });
      } on AudIoException catch (error) {
        _status = 'Stream failed: $error';
      }
    } else {
      _stopSustained();
      _statsTimer?.cancel();
      stream.close();
      _stream = null;
    }
    setState(() {});
  }

  void _selectChain(Chain chain) {
    _chain = chain;
    _engine.setChain(switch (chain) {
      Chain.sineTremolo => [_sine, _tremolo],
      Chain.sampler => [_sampler],
    });
    setState(() {});
  }

  void _playRandomNote() {
    final previous = _playingNote;
    if (previous != null) _engine.noteOff(_sampler, number: previous);
    final note = _lowestKey + _random.nextInt(_highestKey - _lowestKey + 1);
    _engine.noteOn(_sampler, number: note, velocity: 0.8);
    _playingNote = note;
  }

  void _toggleSustained() {
    if (_noteTimer != null) {
      _stopSustained();
    } else {
      _sustained
        ..reset()
        ..start();
      _playRandomNote();
      _noteTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        _playRandomNote();
      });
    }
    setState(() {});
  }

  void _stopSustained() {
    _noteTimer?.cancel();
    _noteTimer = null;
    _sustained.stop();
    final note = _playingNote;
    if (note != null) _engine.noteOff(_sampler, number: note);
    _playingNote = null;
  }

  // Sends a burst of parameter changes to measure the command latency.
  void _latencyBurst() {
    for (var i = 0; i < 100; i++) {
      _engine.setParam(_sine, 0, _frequency + i % 2);
    }
  }

  void _resetStats() {
    _engine.resetStats();
    _stream?.resetStats();
    setState(() {
      _engineStats = _engine.stats;
      _ioStats = _stream?.stats;
    });
  }

  @override
  void dispose() {
    _stopSustained();
    _statsTimer?.cancel();
    _stream?.close();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    return Scaffold(
      appBar: AppBar(title: const Text('aud_audio spike (ticket 5)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _toggleStream,
            child: Text(stream == null ? 'Start audio' : 'Stop audio'),
          ),
          const SizedBox(height: 8),
          SegmentedButton<Chain>(
            segments: const [
              ButtonSegment(
                value: Chain.sineTremolo,
                label: Text('Sine → tremolo'),
              ),
              ButtonSegment(value: Chain.sampler, label: Text('Sampler')),
            ],
            selected: {_chain},
            onSelectionChanged: (selection) => _selectChain(selection.first),
          ),
          if (_chain == Chain.sineTremolo) ...[
            Text('Frequency: ${_frequency.toStringAsFixed(0)} Hz'),
            Slider(
              min: 100,
              max: 2000,
              value: _frequency,
              onChanged: (value) {
                _frequency = value;
                _engine.setParam(_sine, 0, value);
                setState(() {});
              },
            ),
            Text('Tremolo rate: ${_tremoloRate.toStringAsFixed(1)} Hz'),
            Slider(
              min: 0.1,
              max: 20,
              value: _tremoloRate,
              onChanged: (value) {
                _tremoloRate = value;
                _engine.setParam(_tremolo, AudTremolo.rate, value);
                setState(() {});
              },
            ),
            OutlinedButton(
              onPressed: _latencyBurst,
              child: const Text('Send 100 parameter commands'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _loaded ? _playRandomNote : null,
                  child: const Text('Play a random note'),
                ),
                OutlinedButton(
                  onPressed: _loaded ? _toggleSustained : null,
                  child: Text(
                    _noteTimer == null
                        ? 'Start sustained test'
                        : 'Stop sustained test',
                  ),
                ),
              ],
            ),
            if (_noteTimer != null || _sustained.elapsed > Duration.zero)
              Text(
                'Sustained: ${_sustained.elapsed.inMinutes} min '
                '${_sustained.elapsed.inSeconds % 60} s',
              ),
          ],
          const Divider(),
          Row(
            children: [
              const Text('Measurements', style: TextStyle(fontSize: 18)),
              const Spacer(),
              TextButton(onPressed: _resetStats, child: const Text('Reset')),
            ],
          ),
          if (stream != null) _StreamInfo(stream: stream, stats: _ioStats),
          if (_engineStats != null)
            _EngineInfo(
              stats: _engineStats!,
              blockDurationNs: stream == null || stream.framesPerCallback == 0
                  ? 0
                  : stream.framesPerCallback / stream.sampleRate * 1e9,
            ),
        ],
      ),
    );
  }
}

String _ms(num nanoseconds) => '${(nanoseconds / 1e6).toStringAsFixed(3)} ms';

class _StreamInfo extends StatelessWidget {
  const _StreamInfo({required this.stream, required this.stats});

  final AudIoStream stream;
  final AudIoStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final expected = stream.framesPerCallback / stream.sampleRate * 1e9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Backend: ${stream.backendName}'),
        Text(
          'Stream: ${stream.sampleRate.toStringAsFixed(0)} Hz, '
          '${stream.channels} channels, '
          '${stream.framesPerCallback} frames per callback '
          '(${_ms(expected)})',
        ),
        if (s != null) ...[
          Text(
            'Callbacks: ${s.callbacks}, frames ${s.framesMin}..${s.framesMax}, '
            'late: ${s.lateCallbacks}, xruns: ${s.xruns}, '
            'disconnects: ${s.disconnects}',
          ),
          Text(
            'Callback period mean/min/max: ${_ms(s.periodMeanNs)} / '
            '${_ms(s.periodMinNs)} / ${_ms(s.periodMaxNs)}',
          ),
          Text(
            'Callback time mean/max: ${_ms(s.callbackTimeMeanNs)} / '
            '${_ms(s.callbackTimeMaxNs)}'
            '${expected == 0 ? '' : ' (${(s.callbackTimeMaxNs / expected * 100).toStringAsFixed(1)} % of the block at max)'}',
          ),
          if (s.outputLatencyMs > 0)
            Text('Output latency: ${s.outputLatencyMs.toStringAsFixed(2)} ms'),
        ],
      ],
    );
  }
}

class _EngineInfo extends StatelessWidget {
  const _EngineInfo({required this.stats, required this.blockDurationNs});

  final AudEngineStats stats;
  final double blockDurationNs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Engine: ${stats.blocksRendered} blocks, revision '
          '${stats.programRevision}',
        ),
        Text(
          'Render time mean/max: ${_ms(stats.renderTimeMeanNs)} / '
          '${_ms(stats.renderTimeMaxNs)}',
        ),
        Text('Output peak: ${stats.outputPeak.toStringAsFixed(3)}'),
        Text(
          'Commands applied/rejected: ${stats.commandsApplied} / '
          '${stats.commandsRejected}',
        ),
        Text(
          'Command latency mean/min/max: ${_ms(stats.commandLatencyMeanNs)} / '
          '${_ms(stats.commandLatencyMinNs)} / ${_ms(stats.commandLatencyMaxNs)}'
          '${blockDurationNs == 0 ? '' : ' (block ${_ms(blockDurationNs)})'}',
        ),
      ],
    );
  }
}
