<!--
@license
Copyright (c) Audanika. All Rights Reserved.

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Show only the engine in the example and put it into the pub workspace

## Motivation

- An example shows what its package provides. The example of this package
  also had a MIDI keyboard page, built on a MIDI bridge that is not part of
  this package.
- That bridge depends on this package. Through the MIDI page the example
  depended on a package that depends on the package of the example.
- With that loop the example could not join the pub workspace of the repo:
  it resolved on its own, with its own `pubspec.lock` and a committed
  `pubspec_overrides.yaml` that pointed back to local checkouts.
- Without the MIDI page the example shows the engine alone and resolves
  together with the package, like the examples of the other repos of the
  family.

## Strategy

- Remove the MIDI page and everything only it needed; keep the oscillator
  and the sampler pages as they are.
- Put the example into the pub workspace of the repo and drop the files the
  separate resolution needed.
- Keep the library and its public API untouched.
- Describe the engine's extension point without naming a user of it.

## Implementation 1: The example shows the engine

- `example/lib/midi_page.dart` and the MIDI integration tests
  (`midi_test.dart`, `midi_paths_test.dart`, `midi_keyboard_test.dart`,
  `midi_support.dart`) are gone.
- `main.dart` registers the sampler only and shows two pages: oscillator ->
  filter -> output, and the SFZ sampler with its keyboard.
- The Android manifest loses the MIDI and Bluetooth features and
  permissions and the MIDI loopback service with its device description;
  `Info.plist` loses the Bluetooth and local network usage texts.
- The example no longer depends on a MIDI bridge, `aud_midi`,
  `permission_handler` and `ffi`. It keeps `aud_midi_standard` for the
  messages the sampler page plays.

## Implementation 2: The pub workspace

- `pubspec.yaml` declares `workspace: [example]`, `example/pubspec.yaml`
  `resolution: workspace`; one `pubspec.lock` at the root resolves both.
- `example/pubspec.lock` and `example/pubspec_overrides.yaml` are deleted.
- The `test` dev dependency moves from `^1.33.0` to `^1.31.1`: Flutter 3.47
  pins `test_api` 0.7.12 through `flutter_test` of the example, and
  `test` 1.33.0 needs 0.7.15. The other workspace repos of the family use
  the same bound.
- `flutter analyze` covers the example from the root now.

## Implementation 3: Documentation

- The README, in English and German, describes the two pages and the
  workspace and drops the MIDI test commands.
- `AudEngineExtension` and the README call the extension a MIDI bridge in
  general, not a specific package.
- `index.jsonc` describes the example without the MIDI page.

## Result

- `flutter pub get` at the root resolves package and example together.
- Analyzer, formatter and the 130 unit tests are green.

## Open Points

- The integration tests of the two pages ran on no device in this change;
  their code is unchanged.
