# aud_audio

Die Audanika Audio Engine: ein Flutter-Audiograph, in Dart beschrieben und
in C++ gerendert. `AudEngine` spielt einen Graphen von `aud_audio_graph`
über einen Ausgabestream von `aud_audio_io`, registriert die Knotentypen
von DSP-Paketen und erholt sich selbst von Routenwechseln,
Unterbrechungen und verlorenen Geräten. Zuerst iOS und Android.

Teil der Audanika Audio Engine; geplant in [aud_audio_pm](https://github.com/audaudio/aud_audio_pm).

## Ziele

- Eine Engine für die App: Session, Stream und Graph gemeinsam geöffnet,
  die Renderfunktion des Graphen an den Stream übergeben (Ticket 22,
  Schritt S4)
- Explizite Zustände - created, prepared, running, suspended, stopped,
  disposed - und eine Abfolge für jeden Format- oder Routenwechsel, für
  Unterbrechungen und verlorene Geräte; Transport, Graph und Knoten
  bleiben erhalten (Entscheidung lifecycle-001)
- DSP-Pakete registrieren sich über
  `aud_<package>_register(const AudHostApi*)`; ein Paket einer anderen
  ABI-Hauptversion wird abgewiesen (abi-001)
- Eine API auf nativen Plattformen und im Web (web-001): `aud_audio.dart`
  importiert kein `dart:ffi`; die Web-Engine folgt mit S5
- Die ersten Zahlen von S24: Renderzeit, Xruns und
  Command-to-Sound-Latenz

## Installation

```yaml
dependencies:
  aud_audio:
    git:
      url: git@github.com:audaudio/aud_audio.git
      tag_pattern: "{{version}}"
    version: ^0.2.0
```

Das Paket braucht das Flutter SDK, wie `aud_audio_io`. Es pinnt exakte
Versionen von `aud_audio_core`, `aud_audio_graph`, `aud_audio_io` und
`aud_audio_web` (family-001). Seine Plattformen sind iOS und Android
(release-001); macOS, Windows und Linux laufen bis S3b auf dem
Null-Gerät.

## Dokumentation

- [Die Engine](https://audaudio.github.io/engine/) auf der
  Dokumentationsseite
- [Der Plan von Ticket 22](https://github.com/audaudio/aud_audio_pm/blob/main/doc/2026-Q4/tickets/2026-10-09-22-build-the-aud-audio-engine.md)
  mit Entscheidungen, Messungen und Erkenntnissen
- Die Guides in [`doc/guides`](doc/guides)

## Code-Beispiele

Oszillator, Filter und Ausgang:

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

Ein DSP-Paket registriert seine Knotentypen beim Start
(`aud_audio_ffi.dart` auf nativen Plattformen):

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
print(engine.registrations); // AUD_OK, oder z. B. AUD_ERROR_ABI_MAJOR
```

Die Zahlen und ein Bericht zum Kopieren:

```dart
await engine.measureCommandToSound();
print(engine.numbers.toJson());
print(engine.report());
```

`example/` spielt Oszillator -> Filter -> Ausgang mit Frequenz und
Cutoff, Start und Stopp, der aktuellen Route und einem kopierbaren
Bericht:

```bash
cd example
flutter run -d <ios simulator | android emulator | device>
flutter test integration_test/engine_test.dart -d <device> \
  --dart-define=AUD_MEASURE_SECONDS=600
```

## Funktionsweise

- Die Engine öffnet eine `AudIoSession`, erzeugt den `AudGraph` und
  öffnet einen Ausgabe-`AudIoStream` mit `aud_graph_render` und dem
  Graphen als User; `prepare` registriert die Pakete und bereitet den
  Graphen auf Rate und Blockgröße des Streams vor.
- Die Steuerung läuft in Dart auf dem Control-Thread. Nach einem
  Formatwechsel hält der Stream den Graphen an und spielt Stille; die
  Engine suspendiert den Graphen, bereitet ihn neu vor, setzt ihn fort und
  bestätigt dem Stream die Generation des Formats. Unterbrechungen und
  verlorene Geräte suspendieren den Graphen, bis der Stream ihr Ende
  meldet.
- Das Herunterfahren kehrt den Start um: Stream, Graph, Session.
- Command-to-Sound läuft von der Host-Zeit einer leeren Transaktion bis
  zur Ausgabezeit des ersten Blocks, der sie rendert: Der Graph meldet die
  Sample-Position des Blocks, die letzte `AudStreamTime` des Streams
  bildet sie auf den Zeitpunkt ab, an dem er den Ausgang erreicht.
- `aud_audio.dart` exportiert die plattformneutralen APIs der Familie;
  `aud_audio_ffi.dart` ergänzt `AudEngineFfi`, `AudNativeNodePackage` und
  die nativen Teile von Core, Graph und IO.
- `test_packages/aud_test_nodes` ist ein getrennt gebautes DSP-Paket; es
  beweist die Registry. `node scripts/test-native.js` führt seinen
  nativen Test unter ASan/UBSan und dem RealtimeSanitizer aus.

## Mitwirken

Tickets laufen über den `gg`-Workflow: siehe den
[Develop Guide](doc/guides/develop-guide.md) und den
[Review Guide](doc/guides/for-ai/ai-review-guide.md).
