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

import 'engine_panel.dart';
import 'instruments.dart';
import 'keyboard.dart';

// #############################################################################
/// The sampler page: an instrument of generated samples on the SFZ sampler,
/// played with a multi-touch keyboard, sustain and modulation, with the
/// load, the numbers, a test of 64 voices and an auto-play with an animated
/// UI for the runs of ten minutes.
class SamplerPage extends StatefulWidget {
  /// Creates the page on [engine], which knows the sampler; [instrument]
  /// completes with the samples on the device.
  const SamplerPage({
    super.key,
    required this.engine,
    required this.instrument,
  });

  /// The engine.
  final AudEngine engine;

  /// The samples of the instruments on the device.
  final Future<AudSfzTestInstrument> instrument;

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

  /// The load that runs or ran last; the page follows its progress.
  AudLoad? load;

  /// The voices sfizz reported last.
  int voices = 0;

  /// Notes the page plays itself: the test of many voices and the
  /// auto-play.
  final Set<int> sounding = {};

  /// Whether the auto-play runs.
  bool get autoPlaying => _autoPlay != null;

  @override
  void initState() {
    super.initState();
    unawaited(_setUp());
  }

  @override
  void dispose() {
    _stopAutoPlayTimer();
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
  /// plays the old instrument until the new one swaps in. A newer load
  /// takes the place of this one on the page. Throws a [StateError]
  /// before the sampler is set up.
  Future<AudLoad> selectInstrument(int index) async {
    final graph = engine.graph;
    final sampler = node;
    final written = instrument;
    if (sampler == null || written == null) {
      throw StateError('The sampler is not set up yet');
    }
    final sfz = Instruments.sfz(index);
    graph.setString(sampler, AudSfzSampler.sfzVirtualPath, written.sfzPath);
    final id = graph.setString(sampler, AudSfzSampler.sfzText, sfz);
    instrumentIndex = index;
    load = graph.loadOf(id);
    setState(() {});
    final ended = await graph.loadEnded(id);
    if (mounted && load?.id == id) setState(() => load = ended);
    return ended;
  }

  /// Plays [note] with [velocity], 1 to 127.
  void noteOn(int note, int velocity) =>
      _send(MidiNoteOn(channel: 0, note: note, velocity: velocity));

  /// Releases [note].
  void noteOff(int note) => _send(MidiNoteOff(channel: 0, note: note));

  /// Holds or lifts the sustain pedal.
  void setSustain(bool down) {
    _sustain = down;
    _send(
      MidiControlChange(
        channel: 0,
        controller: MidiControllers.sustainPedal,
        value: down ? _controlMax : 0,
      ),
    );
    setState(() {});
  }

  /// Moves the modulation wheel from 0 to 1; it opens the filter.
  void setModulation(double value) {
    _modulation = value;
    _send(
      MidiControlChange(
        channel: 0,
        controller: MidiControllers.modulationWheel,
        value: (value * _controlMax).round(),
      ),
    );
    setState(() {});
  }

  /// Sets the volume of the sampler in dB; nothing before the sampler is
  /// set up.
  void setVolume(double db) {
    final sampler = node;
    if (sampler == null) return;
    _volume = db;
    engine.graph.setParam(
      sampler,
      AudSfzSampler.volume,
      db,
      rampFrames: _rampFrames,
    );
    setState(() {});
  }

  // ...........................................................................
  /// Plays [count] notes at once from [firstVoiceNote] up, at
  /// [voiceVelocity], until [releaseVoices].
  void playVoices(int count) {
    for (var note = firstVoiceNote; note < firstVoiceNote + count; note++) {
      sounding.add(note);
      noteOn(note, voiceVelocity);
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
    _autoPlay = Timer.periodic(_autoPlayInterval, (_) => _playStep(step += 1));
    setState(() {});
  }

  /// Stops the auto-play and releases its notes.
  void stopAutoPlay() {
    _stopAutoPlayTimer();
    releaseVoices();
  }

  // ...........................................................................
  @override
  Widget build(BuildContext context) {
    final numbers = engine.numbers;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EngineHeader(
          engine: engine,
          onToggled: _rebuild,
          keys: 'sampler-',
          trailing: _spinner(),
        ),
        const SizedBox(height: 8),
        _instrumentPicker(),
        const SizedBox(height: 8),
        _loadStatus(),
        if (_error != null) Text(_error!, key: const Key('sampler-error')),
        const SizedBox(height: 8),
        SizedBox(
          height: _keyboardHeight,
          child: Keyboard(
            key: const Key('keyboard'),
            onNoteOn: noteOn,
            onNoteOff: noteOff,
            sounding: sounding,
          ),
        ),
        _pedals(),
        _volumeSlider(),
        _voiceButtons(),
        const Divider(),
        Text('Voices: $voices', key: const Key('voices')),
        EngineNumbers(
          engine: engine,
          numbers: numbers,
          keys: 'sampler-',
          children: [_cache(numbers)],
        ),
      ],
    );
  }

  // ...........................................................................
  /// The lowest note of [playVoices]: 64 notes from it play every sample
  /// of the instruments.
  static const int firstVoiceNote = 30;

  /// The velocity of [playVoices].
  static const int voiceVelocity = 100;

  /// The voices of the test of many voices: the polyphony of the sampler.
  static const int testVoices = 64;

  // ######################
  // Private
  // ######################

  // How often the page asks for the voices, follows the load and shows the
  // numbers.
  static const Duration _refreshInterval = Duration(milliseconds: 200);

  // The time from one step of the auto-play to the next.
  static const Duration _autoPlayInterval = Duration(milliseconds: 120);

  // The seed of the auto-play: every run plays the same notes.
  static const int _seed = 25;

  // Every so many steps the auto-play releases what played, and plays a
  // chord instead of a single note.
  static const int _releaseEvery = 4;
  static const int _chordEvery = 8;

  // The roots of the auto-play: an octave up from C3, a major triad on
  // them, or a single note an octave above.
  static const int _lowestRoot = 48;
  static const int _octave = 12;
  static const List<int> _majorTriad = [0, 4, 7];

  // The velocities of the auto-play: from the softest, spread over the
  // range.
  static const int _softestVelocity = 40;
  static const int _velocitySpread = 80;

  // The steps of the auto-play per radian of its modulation sweep: one
  // sweep takes about 15 s.
  static const double _modulationSteps = 20;

  // The largest value of a MIDI 1.0 control change.
  static const int _controlMax = 127;

  // The frames over which the volume moves to a new value.
  static const int _rampFrames = 256;

  // The height of the keyboard.
  static const double _keyboardHeight = 160;

  // One turn of the icon that spins while the auto-play runs.
  static const Duration _spinTurn = Duration(seconds: 2);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _spinTurn,
  );
  final Random _random = Random(_seed);
  StreamSubscription<AudNodeMessage>? _messages;
  Timer? _refresh;
  Timer? _autoPlay;
  bool _sustain = false;
  double _modulation = 0;
  double _volume = 0;
  String? _error;

  // Waits for the instrument, then creates the sampler, connects it to the
  // output and loads the first instrument.
  Future<void> _setUp() async {
    try {
      final written = await widget.instrument;
      if (!mounted) return;
      instrument = written;
      // The packages register when the engine prepares for the first time.
      if (engine.registrations.isEmpty) engine.prepare();
      final graph = engine.graph;
      final created = graph.createNode(AudSfzSampler.typeId);
      graph.transaction((tx) => tx.connect(created, graph.io));
      node = created;
      _volume = created.descriptor.param(AudSfzSampler.volume)!.defaultValue;
      _messages = graph.messages.listen(_onMessage);
      _refresh = Timer.periodic(_refreshInterval, (_) => _onRefresh());
      await selectInstrument(0);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // Selects the instrument [index] from the picker; an error shows on the
  // page.
  Future<void> _select(int index) async {
    _error = null;
    try {
      await selectInstrument(index);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // One step of the auto-play: now and then it releases what played, then
  // it plays a chord or a single note and sweeps the modulation.
  void _playStep(int step) {
    if (step % _releaseEvery == 0) releaseVoices();
    final root = _lowestRoot + _random.nextInt(_octave);
    final notes = step % _chordEvery == 0
        ? [for (final interval in _majorTriad) root + interval]
        : [root + _octave];
    for (final note in notes) {
      sounding.add(note);
      noteOn(note, _softestVelocity + _random.nextInt(_velocitySpread));
    }
    setModulation((sin(step / _modulationSteps) + 1) / 2);
  }

  void _stopAutoPlayTimer() {
    _autoPlay?.cancel();
    _autoPlay = null;
    if (_spin.isAnimating) _spin.stop();
  }

  void _send(MidiMessage message) {
    final sampler = node;
    if (sampler == null || engine.graph.isDisposed) return;
    for (final event in AudUmpEvent.fromMessage(message)) {
      engine.graph.sendEvent(sampler, event);
    }
  }

  // Asks sfizz for its voices, follows the progress of a load that runs
  // and shows the numbers.
  void _onRefresh() {
    _askVoices();
    final current = load;
    if (current != null && current.isRunning) {
      load = engine.graph.loadOf(current.id) ?? current;
    }
    if (mounted) setState(() {});
  }

  // Asks sfizz how many voices play; the answer comes on the messages.
  void _askVoices() {
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

  void _rebuild() => setState(() {});

  // ...........................................................................
  Widget _spinner() => RotationTransition(
    turns: _spin,
    child: Icon(
      Icons.album,
      color: autoPlaying ? Theme.of(context).colorScheme.primary : null,
    ),
  );

  Widget _instrumentPicker() => SegmentedButton<int>(
    key: const Key('instruments'),
    segments: [
      for (var i = 0; i < Instruments.names.length; i++)
        ButtonSegment(value: i, label: Text(Instruments.names[i])),
    ],
    selected: {instrumentIndex},
    onSelectionChanged: node == null
        ? null
        : (selection) => unawaited(_select(selection.first)),
  );

  Widget _loadStatus() {
    final current = load;
    final status = switch (current) {
      null => 'Writing the instrument...',
      AudLoad(isRunning: true) =>
        'Loading ${Instruments.names[instrumentIndex]}...',
      AudLoad(:final resultName, :final duration, :final message) =>
        '$resultName in ${duration?.inMilliseconds ?? 0} ms'
            '${message.isEmpty ? '' : ': $message'}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          key: const Key('load-progress'),
          value: current?.progress ?? 0,
        ),
        Text(status, key: const Key('load')),
      ],
    );
  }

  Widget _pedals() => Row(
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
  );

  // The slider covers the range of the parameter once the sampler exists.
  Widget _volumeSlider() {
    final range = node?.descriptor.param(AudSfzSampler.volume);
    return Row(
      children: [
        Text('Volume ${_volume.toStringAsFixed(0)} dB'),
        Expanded(
          child: Slider(
            key: const Key('volume'),
            value: range == null ? 0 : _volume,
            min: range?.min ?? 0,
            max: range?.max ?? 1,
            onChanged: range == null ? null : setVolume,
          ),
        ),
      ],
    );
  }

  Widget _voiceButtons() {
    final running = isRunning(engine);
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton(
          key: const Key('voices-64'),
          onPressed: running && sounding.isEmpty && !autoPlaying
              ? () => playVoices(testVoices)
              : null,
          child: const Text('$testVoices voices'),
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
    );
  }

  Widget _cache(AudEngineNumbers numbers) {
    String mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);
    return Text(
      'Cache: ${mb(numbers.cacheBytes)} of ${mb(numbers.cacheBudget)} MB; '
      'loads: longest ${ms(numbers.loadTimeMaxNs)} ms, '
      'failed ${numbers.loadsFailed}',
      key: const Key('cache'),
    );
  }
}
