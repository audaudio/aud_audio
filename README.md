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
  latency

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
  packages: [
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

`example/` plays oscillator -> filter -> output with frequency and cutoff,
start and stop, the current route and a copyable report:

```bash
cd example
flutter run -d <ios simulator | android emulator | device>
flutter test integration_test/engine_test.dart -d <device> \
  --dart-define=AUD_MEASURE_SECONDS=600
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
- Shutdown reverses start-up: stream, graph, session.
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
