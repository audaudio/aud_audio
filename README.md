# aud_audio

The Audanika Audio Engine: a Flutter audio graph defined in Dart and
rendered in C++. `AudEngine` plays a graph of `aud_audio_graph` through an
output stream of `aud_audio_io`, registers the node types of DSP packages
and recovers from route changes, interruptions and lost devices on its
own. iOS and Android first.

Part of the Audanika Audio Engine; planned in [aud_audio_pm](https://github.com/audaudio/aud_audio_pm).

## Goals

- One engine for the app: session, stream and graph opened together, the
  graph's render function handed to the stream (ticket 22, step S4)
- Explicit states - created, prepared, running, suspended, stopped,
  disposed - and one sequence for every change of format or route,
  interruptions and lost devices; the transport, the graph and its nodes
  survive (decision lifecycle-001)
- DSP packages register through `aud_<package>_register(const AudHostApi*)`;
  a package of another ABI major is refused (abi-001)
- One API on native platforms and the web (web-001):
  `aud_audio.dart` imports no `dart:ffi`; the web engine follows with S5
- The first numbers of S24: render time, xruns and command-to-sound
  latency; since ticket 25 the sample cache and the loads of the nodes
- One sample cache budget for the process, set through `AudEngineConfig`
  (lifecycle-002)

## Installation

```yaml
dependencies:
  aud_audio:
    git:
      url: git@github.com:audaudio/aud_audio.git
      tag_pattern: "{{version}}"
    version: ^0.2.0
```

The package needs the Flutter SDK, as `aud_audio_io` does. It pins exact
versions of `aud_audio_core`, `aud_audio_graph`, `aud_audio_io` and
`aud_audio_web` (family-001). Its platforms are iOS and Android
(release-001); macOS, Windows and Linux run the null device until S3b.

## Documentation

- [The engine](https://audaudio.github.io/engine/) on the documentation
  site
- [The plan of ticket 22](https://github.com/audaudio/aud_audio_pm/blob/main/doc/2026-Q4/tickets/2026-10-09-22-build-the-aud-audio-engine.md)
  with its decisions, measurements and findings
- [The plan of ticket 25](https://github.com/audaudio/aud_audio_pm/blob/main/doc/2026-Q4/tickets/2026-10-11-25-build-the-sfz-sampler-on-sfizz-for-ios-and-android.md)
  with the sampler, its measurements and findings
- The guides in [`doc/guides`](doc/guides)

## Code Examples

Oscillator, filter and output:

```dart
import 'package:aud_audio/aud_audio.dart';

void main() {
  final engine = AudEngine();
  final graph = engine.graph;
  final osc = graph.createNode('aud.graph.oscillator');
  final filter = graph.createNode('aud.graph.filter');
  graph.transaction(
    (tx) => tx
      ..connect(osc, filter)
      ..connect(filter, graph.io),
  );
  graph.setParam(filter, 'cutoff', 1200);
  engine.start();
}
```

A DSP package registers its node types at the start
(`aud_audio_ffi.dart` on native platforms):

```dart
final engine = AudEngine(
  config: const AudEngineConfig(cacheBudget: 128 << 20),
  packages: [
    // The SFZ sampler of aud_dsp_sampler; the app depends on it.
    AudNativeNodePackage(AudDspSampler.name, AudDspSampler.register),
    AudNativeNodePackage(
      'aud_dsp_effects',
      Native.addressOf(aud_dsp_effects_register),
    ),
  ],
);
engine.prepare();
print(engine.registrations); // AUD_OK, or e.g. AUD_ERROR_ABI_MAJOR
```

The numbers and a report to copy:

```dart
await engine.measureCommandToSound();
print(engine.numbers.toJson());
print(engine.report());
```

A governor keeps a budget of voices within what the device renders in its
block (ticket 29). The app binds the budget of a DSP package - the voice
budget of the sampler nodes of `aud_dsp_sampler` - to `AudLoadBudget`:

```dart
final governor = AudLoadGovernor(
  budget: samplerVoices, // an AudLoadBudget of the app
  start: learnedBudget ?? AudDeviceClass.current().startUnits,
);
engine.addExtension(governor);
engine.start();
governor.states.listen((state) => print(state.budget));
```

`AudLoadGovernorConfig` sets the period, the window, the band (`upBelow`,
`target`, `downAbove`), floor, ceiling, step, hold and settle time.
`states` emits an `AudLoadGovernorState` with its `AudLoadAction` per
period; `AudLoadBudget.usage` returns an `AudLoadBudgetUsage`;
`AudDeviceClass.key` names the device for a learned budget, and
`AudDeviceClass.fromProbe` reads an `AudDeviceProbe` (tests).

`example/` has three pages on one engine: oscillator -> filter -> output
with frequency and cutoff; the SFZ sampler of `aud_dsp_sampler` with
instruments generated on the device, a multi-touch keyboard, sustain,
modulation, the load, a test of 64 voices and an auto-play with an animated
UI; and the MIDI keyboard of ticket 26: a port of `aud_midi` plays the
sampler through `aud_audio_midi`, with a port picker, Bluetooth MIDI, the
activity of the port, the fixed or immediate timing and the measured input
to output time. All with the numbers and a copyable report.
`sampler_test.dart` measures the M1 budgets of ticket 17;
`AUD_WARMUP_SECONDS` lets the auto-play warm the device up first, and only
the xruns of the following `AUD_MEASURE_SECONDS` count. `midi_test.dart`
plays a recorded performance from a source of the app into the MIDI page
the same way, `midi_paths_test.dart` measures the native and the Dart
paths of midi-002, and `midi_keyboard_test.dart` guides a person through
playing a real keyboard, the hot-plug and Bluetooth MIDI:

```bash
cd example
flutter run -d <ios simulator | android emulator | device>
flutter test integration_test/engine_test.dart -d <device> \
  --dart-define=AUD_MEASURE_SECONDS=600
flutter test integration_test/sampler_test.dart -d <device> \
  --dart-define=AUD_WARMUP_SECONDS=1200 \
  --dart-define=AUD_MEASURE_SECONDS=600 --dart-define=AUD_ASSERT_BUDGETS=true
flutter test integration_test/midi_test.dart -d <device> \
  --dart-define=AUD_WARMUP_SECONDS=1200 --dart-define=AUD_MEASURE_SECONDS=600
flutter test integration_test/midi_keyboard_test.dart -d <device> \
  --dart-define=AUD_PLAY_SECONDS=600 --dart-define=AUD_BLUETOOTH=true
```

## How It Works

- The engine opens an `AudIoSession`, creates the `AudGraph` and opens an
  output `AudIoStream` with `aud_graph_render` and the graph as its user;
  `prepare` registers the packages and prepares the graph for the
  stream's rate and block size.
- The glue runs in Dart on the control thread. After a change of the
  format the stream holds the graph and plays silence; the engine
  suspends the graph, prepares it again, resumes it and acknowledges the
  format's generation to the stream. Interruptions and lost devices
  suspend the graph until the stream reports them over.
- Shutdown reverses start-up: stream, graph, session. Before, the engine
  tells its extensions (`AudEngineExtension`, e.g. the MIDI bridge of
  `aud_audio_midi`), newest first and synchronously, so that they stop
  what feeds the graph from other threads; extensions also hear when the
  engine started, stops and when its timing starts again.
- `AudEngine.timing` is the graph's timing of the last block for the
  control side: the fitted output time, the reported output latency and
  the gaps between renders (midi-003).
- `AudLoadGovernor` is an extension that looks at the load every 100 ms
  on the control thread while the engine runs: the mean share of its
  block the renders took over the last second (`AudGraph.renderLoad`),
  the xruns of the stream and the units of its `AudLoadBudget`. Its
  `AudLoadPolicy` lowers the budget at once on an xrun or a mean above
  85 % and raises it by a unit per period only while the mean stays below
  72 % and the budget limits. It fits a line through the mean shares over
  the units in use of the last seconds and lowers the budget to the units
  that keep the mean at 75 %, no deeper than the units in use scaled to
  it. The mean, not the p99, tells when a stream drops out: on
  the Galaxy Tab S4 the note-on bursts of the stress test make a few
  renders long at any number of voices, and the device buffer absorbs
  them (ticket 29). It starts from the budget the app learned on the
  device or from `AudDeviceClass.startUnits`: the performance cores on
  iOS, the media performance class and the clock of the fastest cores on
  Android, 128 on a simulator or emulator, read from the system through
  the C library; ticket 30 raised these start units for the faster
  sampler voices (lifecycle-004).
  The policy runs without timers, so recorded `AudLoadSample`s replay
  through it.
- Command-to-sound runs from the host time of an empty transaction to the
  presentation time of the first block that renders it: the graph reports
  the block's sample position, the stream's last `AudStreamTime` maps it
  to the time it reaches the output.
- `aud_audio.dart` exports the platform-neutral APIs of the family;
  `aud_audio_ffi.dart` adds `AudEngineFfi`, `AudNativeNodePackage` and the
  native parts of core, graph and io.
- `test_packages/aud_test_nodes` is a DSP package built apart from the
  engine: `node scripts/test-native.js --library` builds it as a library
  of its own, which the tests load to prove the registry. `node scripts/test-native.js` runs its
  native test under ASan/UBSan and the RealtimeSanitizer.

## Contributing

Tickets run through the `gg` workflow: see the
[Develop Guide](doc/guides/develop-guide.md) and the
[Review Guide](doc/guides/for-ai/ai-review-guide.md).
