# aud_audio

Die Audanika Audio Engine: ein Flutter-Audiograph, in Dart beschrieben und
in C++ gerendert. `AudEngine` spielt einen Graphen von `aud_audio_graph`
über einen Ausgabestream von `aud_audio_io`, registriert die Knotentypen
von DSP-Paketen und erholt sich selbst von Routenwechseln,
Unterbrechungen und verlorenen Geräten. Zuerst iOS und Android, macOS mit
der Audanika-Mac-App.

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
  Command-to-Sound-Latenz; seit Ticket 25 der Sample-Cache und die
  Ladevorgänge der Knoten
- Ein Sample-Cache-Budget für den Prozess, gesetzt über
  `AudEngineConfig` (lifecycle-002)

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
(release-001) und macOS auf dem Core-Audio-Gerät von `aud_audio_io`
(release-005, Ticket 37); Windows und Linux laufen bis S3c und S3d auf
dem Null-Gerät.

## Dokumentation

- [Die Engine](https://audaudio.github.io/engine/) auf der
  Dokumentationsseite
- [Der Plan von Ticket 22](https://github.com/audaudio/aud_audio_pm/blob/main/doc/2026-Q4/tickets/2026-10-09-22-build-the-aud-audio-engine.md)
  mit Entscheidungen, Messungen und Erkenntnissen
- [Der Plan von Ticket 25](https://github.com/audaudio/aud_audio_pm/blob/main/doc/2026-Q4/tickets/2026-10-11-25-build-the-sfz-sampler-on-sfizz-for-ios-and-android.md)
  mit dem Sampler, seinen Messungen und Erkenntnissen
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
  config: const AudEngineConfig(cacheBudget: 128 << 20),
  packages: [
    // Der SFZ-Sampler von aud_dsp_sampler; die App hängt von ihm ab.
    AudNativeNodePackage(AudDspSampler.name, AudDspSampler.register),
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

Ein Governor hält ein Budget an Stimmen in dem, was das Gerät in seinem
Block rendert (Ticket 29). Die App bindet das Budget eines DSP-Pakets - das
Stimmenbudget der Sampler-Knoten von `aud_dsp_sampler` - an
`AudLoadBudget`:

```dart
final governor = AudLoadGovernor(
  budget: samplerVoices, // ein AudLoadBudget der App
  start: learnedBudget ?? AudDeviceClass.current().startUnits,
);
engine.addExtension(governor);
engine.start();
governor.states.listen((state) => print(state.budget));
```

`AudLoadGovernorConfig` setzt Periode, Fenster, das Band (`upBelow`,
`target`, `downAbove`), Boden, Decke, Schritt, Halte- und Einschwingzeit.
`states` liefert je Periode einen `AudLoadGovernorState` mit seiner
`AudLoadAction`; `AudLoadBudget.usage` liefert eine `AudLoadBudgetUsage`;
`AudDeviceClass.key` benennt das Gerät für ein gelerntes Budget, und
`AudDeviceClass.fromProbe` liest eine `AudDeviceProbe` (Tests).

`example/` hat drei Seiten auf einer Engine: Oszillator -> Filter ->
Ausgang mit Frequenz und Cutoff; den SFZ-Sampler von `aud_dsp_sampler`
mit Instrumenten, die auf dem Gerät erzeugt werden, einer
Multi-Touch-Tastatur, Sustain, Modulation, dem Ladevorgang, einem Test mit
64 Stimmen und einem Auto-Play mit animierter UI; und das MIDI-Keyboard
von Ticket 26: Ein Port von `aud_midi` spielt den Sampler über
`aud_audio_midi`, mit Port-Auswahl, Bluetooth-MIDI, der Aktivität des
Ports, dem festen oder sofortigen Timing und der gemessenen Zeit vom
Eingang zum Ausgang. Alle mit den Zahlen und einem kopierbaren Bericht.
`sampler_test.dart` misst die M1-Budgets von Ticket 17;
`AUD_WARMUP_SECONDS` lässt das Auto-Play das Gerät zuerst aufwärmen, und
nur die Xruns der folgenden `AUD_MEASURE_SECONDS` zählen.
`midi_test.dart` spielt eine aufgenommene Performance aus einer Quelle
der App ebenso in die MIDI-Seite, `midi_paths_test.dart` misst den
nativen und die Dart-Wege von midi-002, und `midi_keyboard_test.dart`
führt eine Person durch das Spielen eines echten Keyboards, das Hot-Plug
und Bluetooth-MIDI:

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
- Das Herunterfahren kehrt den Start um: Stream, Graph, Session. Vorher
  sagt die Engine es ihren Erweiterungen (`AudEngineExtension`, z. B. der
  MIDI-Brücke von `aud_audio_midi`), die neueste zuerst und synchron,
  damit sie anhalten, was den Graphen aus anderen Threads speist;
  Erweiterungen hören auch, wenn die Engine gestartet ist, stoppt und wenn
  ihr Timing neu beginnt.
- `AudEngine.timing` ist das Timing des Graphen aus dem letzten Block für
  die Steuerseite: die angepasste Ausgangszeit, die gemeldete
  Ausgangslatenz und die Abstände zwischen den Renders (midi-003).
- `AudLoadGovernor` ist eine Erweiterung, die alle 100 ms auf dem
  Control-Thread auf die Last schaut, solange die Engine läuft: den
  mittleren Anteil ihres Blocks, den die Renders in der letzten Sekunde
  brauchten (`AudGraph.renderLoad`), die Xruns des Streams und die
  Einheiten ihres `AudLoadBudget`. Ihre `AudLoadPolicy` senkt das Budget
  sofort bei einem Xrun oder einem Mittel über 85 % und hebt es nur um
  eine Einheit je Periode, solange das Mittel unter 72 % bleibt und das
  Budget begrenzt. Sie legt eine Gerade durch die mittleren Anteile über
  den Einheiten der letzten Sekunden und senkt das Budget auf die
  Einheiten, die das Mittel bei 75 % halten, nicht tiefer als die
  Einheiten in Gebrauch, auf das Ziel skaliert. Das Mittel, nicht das
  p99, sagt, wann ein Stream aussetzt: Auf dem Galaxy Tab S4 machen die
  Note-on-Bündel des Stresstests bei jeder Stimmenzahl einige Renders
  lang, und der Gerätepuffer fängt sie auf (Ticket 29). Sie beginnt mit
  dem Budget, das die App auf dem Gerät gelernt hat, oder mit
  `AudDeviceClass.startUnits`: den Performance-Kernen unter iOS, der Media
  Performance Class und dem Takt der schnellsten Kerne unter Android, 128
  auf einem Simulator oder Emulator, gelesen über die C-Bibliothek; Ticket
  30 hob diese Startwerte für die schnelleren Sampler-Stimmen an
  (lifecycle-004). Die
  Policy läuft ohne Timer, deshalb lassen sich aufgezeichnete
  `AudLoadSample`s durch sie abspielen.
- Command-to-Sound läuft von der Host-Zeit einer leeren Transaktion bis
  zur Ausgabezeit des ersten Blocks, der sie rendert: Der Graph meldet die
  Sample-Position des Blocks, die letzte `AudStreamTime` des Streams
  bildet sie auf den Zeitpunkt ab, an dem er den Ausgang erreicht.
- `aud_audio.dart` exportiert die plattformneutralen APIs der Familie;
  `aud_audio_ffi.dart` ergänzt `AudEngineFfi`, `AudNativeNodePackage` und
  die nativen Teile von Core, Graph und IO.
- `test_packages/aud_test_nodes` ist ein getrennt gebautes DSP-Paket:
  `node scripts/test-native.js --library` baut es als eigene Bibliothek,
  die die Tests laden, um die Registry zu beweisen. `node scripts/test-native.js` führt seinen
  nativen Test unter ASan/UBSan und dem RealtimeSanitizer aus.

## Mitwirken

Tickets laufen über den `gg`-Workflow: siehe den
[Develop Guide](doc/guides/develop-guide.md) und den
[Review Guide](doc/guides/for-ai/ai-review-guide.md).
