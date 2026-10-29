<!--
@license
Copyright (c) Audanika. All Rights Reserved.

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Nur die Engine im Beispiel zeigen und es in den Pub-Workspace holen

## Motivation

- Ein Beispiel zeigt, was sein Paket bereitstellt. Das Beispiel dieses
  Pakets hatte auch eine MIDI-Keyboard-Seite, gebaut auf einer MIDI-Brücke,
  die nicht Teil dieses Pakets ist.
- Diese Brücke hängt von diesem Paket ab. Über die MIDI-Seite hing das
  Beispiel also an einem Paket, das selbst am Paket des Beispiels hängt.
- Mit dieser Schleife konnte das Beispiel nicht in den Pub-Workspace des
  Repos: Es löste allein auf, mit eigener `pubspec.lock` und einer
  eingecheckten `pubspec_overrides.yaml`, die auf lokale Checkouts zeigte.
- Ohne die MIDI-Seite zeigt das Beispiel nur die Engine und löst zusammen
  mit dem Paket auf, wie die Beispiele der anderen Repos der Familie.

## Strategie

- Die MIDI-Seite und alles, was nur sie brauchte, entfernen; Oszillator-
  und Sampler-Seite bleiben, wie sie sind.
- Das Beispiel in den Pub-Workspace des Repos holen und die Dateien
  löschen, die die getrennte Auflösung brauchte.
- Die Bibliothek und ihre öffentliche API bleiben unverändert.
- Den Erweiterungspunkt der Engine beschreiben, ohne einen Nutzer zu
  nennen.

## Realisierung 1: Das Beispiel zeigt die Engine

- `example/lib/midi_page.dart` und die MIDI-Integrationstests
  (`midi_test.dart`, `midi_paths_test.dart`, `midi_keyboard_test.dart`,
  `midi_support.dart`) sind weg.
- `main.dart` registriert nur den Sampler und zeigt zwei Seiten:
  Oszillator -> Filter -> Ausgang und den SFZ-Sampler mit seiner Tastatur.
- Das Android-Manifest verliert die MIDI- und Bluetooth-Features und
  -Berechtigungen sowie den MIDI-Loopback-Service mit seiner
  Gerätebeschreibung; `Info.plist` verliert die Texte für Bluetooth und das
  lokale Netzwerk.
- Das Beispiel hängt nicht mehr an einer MIDI-Brücke, `aud_midi`,
  `permission_handler` und `ffi`. `aud_midi_standard` bleibt für die
  Nachrichten, die die Sampler-Seite spielt.

## Realisierung 2: Der Pub-Workspace

- `pubspec.yaml` deklariert `workspace: [example]`, `example/pubspec.yaml`
  `resolution: workspace`; eine `pubspec.lock` im Root löst beide auf.
- `example/pubspec.lock` und `example/pubspec_overrides.yaml` sind
  gelöscht.
- Die Dev-Abhängigkeit `test` geht von `^1.33.0` auf `^1.31.1`: Flutter
  3.47 pinnt über `flutter_test` des Beispiels `test_api` 0.7.12, und
  `test` 1.33.0 braucht 0.7.15. Die anderen Workspace-Repos der Familie
  nutzen dieselbe Grenze.
- `flutter analyze` prüft das Beispiel jetzt vom Root aus mit.

## Realisierung 3: Dokumentation

- Die README, auf Englisch und Deutsch, beschreibt die zwei Seiten und den
  Workspace und verliert die MIDI-Testbefehle.
- `AudEngineExtension` und die README nennen die Erweiterung allgemein eine
  MIDI-Brücke, kein bestimmtes Paket.
- `index.jsonc` beschreibt das Beispiel ohne die MIDI-Seite.

## Ergebnis

- `flutter pub get` im Root löst Paket und Beispiel zusammen auf.
- Analyzer, Formatter und die 130 Unit-Tests sind grün.

## Offene Punkte

- Die Integrationstests der beiden Seiten liefen in dieser Änderung auf
  keinem Gerät; ihr Code ist unverändert.
