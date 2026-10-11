// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:math';

import 'package:aud_audio/aud_audio.dart';
import 'package:aud_dsp_sampler/aud_dsp_sampler.dart';
import 'package:aud_dsp_sampler/testing.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'keyboard.dart';

// #############################################################################
/// The instruments of the page, generated on the device (scope-002): the
/// samples of [AudSfzTestInstrument] with three settings of envelope and
/// filter, each an SFZ text against the instrument's directory.
abstract final class Instruments {
  /// The names of the instruments.
  static const List<String> names = ['Saw pad', 'Pluck', 'Mellow'];

  /// The SFZ text of the instrument [index].
  static String sfz(int index) => switch (index) {
    0 => AudSfzTestInstrument.sfz,
    1 => _withGlobal(
      'ampeg_attack=0.002 ampeg_decay=0.6 ampeg_sustain=0 '
      'ampeg_release=0.15\n'
      'fil_type=lpf_2p cutoff=600 resonance=6 fil_veltrack=3600 '
      'fileg_decay=0.25 fileg_sustain=0 fileg_depth=3600 cutoff_oncc1=2400',
    ),
    _ => _withGlobal(
      'ampeg_attack=0.08 ampeg_decay=0.5 ampeg_sustain=80 '
      'ampeg_release=0.8\n'
      'fil_type=lpf_4p cutoff=350 fil_veltrack=1200 cutoff_oncc1=3600',
    ),
  };

  static String _withGlobal(String opcodes) => AudSfzTestInstrument.sfz
      .replaceFirst(RegExp(r'ampeg_attack[\s\S]*?(?=<region>)'), '$opcodes\n');
}

// #############################################################################
/// The sampler page: an instrument of generated samples on the SFZ sampler,
/// played with a multi-touch keyboard, sustain and modulation, with the
/// load, the numbers, a test of 64 voices and an auto-play with an animated
/// UI for the runs of ten minutes.
class SamplerPage extends StatefulWidget {
  /// Creates the page on [engine], which knows the sampler.
  const SamplerPage({super.key, required this.engine, this.directory});

  /// The engine.
  final AudEngine engine;

  /// Where the instrument is written; the temporary directory by default.
  final String? directory;

  @override
  State<SamplerPage> createState() => SamplerPageState();
}

// #############################################################################
/// The state of [SamplerPage]; public for the integration tests.
class SamplerPageState extends State<SamplerPage>
    with SingleTickerProviderStateMixin {
  /// The engine.
  AudEngine get engine => widget.engine;

  /// The sampler, once the instrument is written.
  AudNode? node;

  /// The instrument on the device.
  AudSfzTestInstrument? instrument;

  /// The instrument that plays or loads.
  int instrumentIndex = 0;

  /// The load that runs or ran last.
  AudLoad? load;

  /// The voices sfizz reported last.
  int voices = 0;

  /// Notes the page plays itself: the 64-voice test and the auto-play.
  final Set<int> sounding = {};

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  final Random _random = Random(25);
  StreamSubscription<AudNodeMessage>? _messages;
  Timer? _refresh;
  Timer? _autoPlay;
  bool _sustain = false;
  double _modulation = 0;
  double _volume = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_setUp());
  }

  Future<void> _setUp() async {
    try {
      final base = widget.directory ?? (await getTemporaryDirectory()).path;
      instrument = AudSfzTestInstrument.write('$base/aud_test_instrument');
      if (!mounted) return;
      // The packages register when the engine prepares for the first time.
      if (engine.registrations.isEmpty) engine.prepare();
      final graph = engine.graph;
      final created = graph.createNode(AudSfzSampler.typeId);
      graph.transaction((tx) => tx.connect(created, graph.io));
      node = created;
      _messages = graph.messages.listen(_onMessage);
      _refresh = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _ask();
        if (mounted) setState(() {});
      });
      await selectInstrument(0);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _stopTimers();
    for (final note in sounding) {
      noteOff(note);
    }
    _refresh?.cancel();
    unawaited(_messages?.cancel());
    _spin.dispose();
    final created = node;
    if (created != null && !engine.graph.isDisposed) {
      engine.graph.transaction((tx) => tx.remove(created));
    }
    super.dispose();
  }

  // ...........................................................................
  /// Loads the instrument [index] and completes with its load: the node
  /// plays the old instrument until the new one swaps in.
  Future<AudLoad> selectInstrument(int index) async {
    final graph = engine.graph;
    final sampler = node!;
    instrumentIndex = index;
    graph.setString(sampler, AudSfzSampler.sfzVirtualPath, instrument!.sfzPath);
    final id = graph.setString(
      sampler,
      AudSfzSampler.sfzText,
      Instruments.sfz(index),
    );
    load = graph.loadOf(id);
    setState(() {});
    final ended = await graph.loadEnded(id);
    if (mounted) setState(() => load = ended);
    return ended;
  }

  /// Plays [note] with [velocity], 1 to 127.
  void noteOn(int note, int velocity) =>
      _send(MidiNoteOn(channel: 0, note: note, velocity: velocity));

  /// Releases [note].
  void noteOff(int note) => _send(MidiNoteOff(channel: 0, note: note));

  /// Holds or lifts the sustain pedal, CC 64.
  void setSustain(bool down) {
    _sustain = down;
    _send(MidiControlChange(channel: 0, controller: 64, value: down ? 127 : 0));
    setState(() {});
  }

  /// Moves the modulation wheel, CC 1, from 0 to 1; it opens the filter.
  void setModulation(double value) {
    _modulation = value;
    _send(
      MidiControlChange(
        channel: 0,
        controller: 1,
        value: (value * 127).round(),
      ),
    );
    setState(() {});
  }

  /// Sets the volume of the sampler in dB.
  void setVolume(double db) {
    _volume = db;
    engine.graph.setParam(node!, AudSfzSampler.volume, db, rampFrames: 256);
    setState(() {});
  }

  /// Plays [count] notes at once from note 30 up, at velocity 100, until
  /// [releaseVoices].
  void playVoices(int count) {
    for (var note = 30; note < 30 + count; note++) {
      sounding.add(note);
      noteOn(note, 100);
    }
    setState(() {});
  }

  /// Releases the notes of [playVoices] and of the auto-play.
  void releaseVoices() {
    for (final note in sounding) {
      noteOff(note);
    }
    sounding.clear();
    setState(() {});
  }

  /// Plays chords and runs of random notes while the UI animates, until
  /// [stopAutoPlay]: the load of the runs of ten minutes.
  void startAutoPlay() {
    if (_autoPlay != null) return;
    _spin.repeat();
    var step = 0;
    _autoPlay = Timer.periodic(const Duration(milliseconds: 120), (_) {
      step += 1;
      // Release what played long enough, then play the next notes.
      if (step % 4 == 0) releaseVoices();
      final root = 48 + _random.nextInt(12);
      final notes = step % 8 == 0 ? [root, root + 4, root + 7] : [root + 12];
      for (final note in notes) {
        sounding.add(note);
        noteOn(note, 40 + _random.nextInt(80));
      }
      setModulation((sin(step / 20) + 1) / 2);
    });
    setState(() {});
  }

  /// Stops the auto-play and releases its notes.
  void stopAutoPlay() {
    _stopTimers();
    releaseVoices();
  }

  void _stopTimers() {
    _autoPlay?.cancel();
    _autoPlay = null;
    if (_spin.isAnimating) _spin.stop();
  }

  /// Whether the auto-play runs.
  bool get autoPlaying => _autoPlay != null;

  // ...........................................................................
  void _send(MidiMessage message) {
    final sampler = node;
    if (sampler == null) return;
    for (final event in AudUmpEvent.fromMessage(message)) {
      engine.graph.sendEvent(sampler, event);
    }
  }

  // Asks sfizz how many voices play; the answer comes on the messages.
  void _ask() {
    final sampler = node;
    if (sampler == null || engine.state != AudEngineState.running) return;
    engine.graph.sendMessage(sampler, AudOscMessage('/num_active_voices'));
  }

  void _onMessage(AudNodeMessage message) {
    if (message.node != node?.handle) return;
    if (message.path == '/num_active_voices' && message.arguments.isNotEmpty) {
      voices = message.arguments.first! as int;
    }
  }

  // ...........................................................................
  @override
  Widget build(BuildContext context) {
    final state = engine.state;
    final running =
        state == AudEngineState.running || state == AudEngineState.suspended;
    final numbers = engine.numbers;
    final current = load;
    final loading = current != null && current.isRunning;
    String ms(num? ns) => ns == null ? '-' : (ns / 1e6).toStringAsFixed(2);
    String mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'State: ${state.name}',
                key: const Key('sampler-state'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            RotationTransition(
              turns: _spin,
              child: Icon(
                Icons.album,
                color: autoPlaying ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('sampler-toggle'),
          onPressed: () => setState(() {
            if (running) {
              engine.stop();
            } else {
              engine.start();
            }
          }),
          child: Text(running ? 'Stop' : 'Start'),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          key: const Key('instruments'),
          segments: [
            for (var i = 0; i < Instruments.names.length; i++)
              ButtonSegment(value: i, label: Text(Instruments.names[i])),
          ],
          selected: {instrumentIndex},
          onSelectionChanged: node == null
              ? null
              : (selection) => unawaited(selectInstrument(selection.first)),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          key: const Key('load-progress'),
          value: current == null ? 0 : current.progress,
        ),
        Text(
          current == null
              ? 'Writing the instrument...'
              : loading
              ? 'Loading ${Instruments.names[instrumentIndex]}...'
              : '${current.resultName} in '
                    '${current.duration?.inMilliseconds ?? 0} ms'
                    '${current.message.isEmpty ? '' : ': ${current.message}'}',
          key: const Key('load'),
        ),
        if (_error != null) Text(_error!, key: const Key('sampler-error')),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: Keyboard(
            key: const Key('keyboard'),
            onNoteOn: noteOn,
            onNoteOff: noteOff,
            sounding: sounding,
          ),
        ),
        Row(
          children: [
            FilterChip(
              key: const Key('sustain'),
              label: const Text('Sustain'),
              selected: _sustain,
              onSelected: setSustain,
            ),
            const SizedBox(width: 16),
            const Text('Modulation'),
            Expanded(
              child: Slider(
                key: const Key('modulation'),
                value: _modulation,
                onChanged: setModulation,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text('Volume ${_volume.toStringAsFixed(0)} dB'),
            Expanded(
              child: Slider(
                key: const Key('volume'),
                value: _volume,
                min: -40,
                max: 6,
                onChanged: setVolume,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              key: const Key('voices-64'),
              onPressed: running && sounding.isEmpty && !autoPlaying
                  ? () => playVoices(64)
                  : null,
              child: const Text('64 voices'),
            ),
            OutlinedButton(
              key: const Key('release'),
              onPressed: sounding.isEmpty ? null : releaseVoices,
              child: const Text('Release'),
            ),
            OutlinedButton(
              key: const Key('auto-play'),
              onPressed: running
                  ? () => autoPlaying ? stopAutoPlay() : startAutoPlay()
                  : null,
              child: Text(autoPlaying ? 'Stop auto-play' : 'Auto-play'),
            ),
          ],
        ),
        const Divider(),
        Text('Voices: $voices', key: const Key('voices')),
        Text(
          'Render: max ${ms(numbers.renderTimeMaxNs)} ms, '
          'mean ${ms(numbers.renderTimeMeanNs)} ms',
        ),
        Text(
          'Callbacks: ${numbers.callbacks}, xruns ${numbers.xruns}, '
          'late ${numbers.lateCallbacks}',
          key: const Key('sampler-callbacks'),
        ),
        Text(
          'Cache: ${mb(numbers.cacheBytes)} of ${mb(numbers.cacheBudget)} MB; '
          'loads: longest ${ms(numbers.loadTimeMaxNs)} ms, '
          'failed ${numbers.loadsFailed}',
          key: const Key('cache'),
        ),
      ],
    );
  }
}
