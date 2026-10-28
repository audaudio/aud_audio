# Changelog

## 0.5.1 - 2026-10-28

### Changed

- Upgrade the git dependencies to their published versions

- Lift aud_audio_core, aud_audio_graph, aud_audio_io, aud_audio_web and aud_dsp_sampler to their published versions

- Let the example resolve on its own again; it depends on aud_audio_midi, which depends on this package

- Upgrade aud_midi and aud_midi_standard in the example

## 0.5.0 - 2026-10-28

### Changed

- Require Dart 3.13 and Flutter 3.47, upgrade deps

- Require Dart 3.13 and Flutter 3.47

- Upgrade dna_audanika to ^0.1.0

- Upgrade helix to ^1.14.0

- Set the identity the DNA layers ask for in dna/_vars.json

- Reformat 3 files with the Dart 3.13 formatter

- Add the blog post of this change, in English and German

- Bring the README to the README template, in English and German

- Upgrade the dependencies published since the first pass

- Lift the lock file to the newest resolvable versions

- Resolve the example together with the package

- Add the example to a pub workspace, resolution: workspace in the example

- Drop the lock file of the example, the package lock covers it

- Move the dependency overrides of the example to the workspace root

- Keep test within the test_api that flutter_test pins

## 0.4.5 - 2026-10-24

### Changed

- Run the native tests on Windows
- Name the Windows device of aud_audio_io in the README

## 0.4.4 - 2026-10-22

### Added

- Add macOS to the platforms of the engine
- pubspec.yaml lists macOS, which aud_audio_io serves with its Core Audio device (release-005)
- README.md, README.de.md and index.jsonc name macOS; Windows and Linux keep the null device until S3c and S3d

## 0.4.3 - 2026-10-15

### Added

- Add higher start budgets for the faster sampler voices

- AudDeviceClass.startUnits rises with the voice loop and the fast cores of ticket 30 (lifecycle-004)

- The class of the Galaxy Tab S4 (fast cores from 2.3 GHz) starts at 96 instead of 32, slower Android devices at 48, faster ones up to 192

- iOS starts at 128 with two performance cores and at 192 with three or more, simulators and emulators at 128

- Add clearer words for the raised start units

- The README says which start units ticket 30 raised

## 0.4.2 - 2026-10-14

### Added

- Add a load governor and the class of the device

- AudLoadGovernor: an engine extension that sets an AudLoadBudget every 100 ms from the mean render share of the last second and the xruns

- AudLoadPolicy: down at once on an xrun or a mean share above 85 %, up by a unit below 72 % while the budget limits; a line through the shares over the units lowers to the units that keep the mean at 75 %

- AudLoadBudget, AudLoadBudgetUsage, AudLoadGovernorConfig, AudLoadGovernorState and AudLoadSample, which replays recorded loads

- AudDeviceClass: the model, the cores, their clocks, the SoC and the media performance class through the C library, and the start budget of a class

- A simulation of the stress test on modeled devices, the Galaxy Tab S4 of the measurements among them

- The governor in the READMEs and the index

- Add a new start of the governor's counters after a pause

- A tick that comes more than three periods late starts the counters again instead of one long period with the renders and xruns of the pause

- The overloads of the state are those of the window, not a sum of periods that overlap

- Add helix ^1.12.0 to the dev dependencies

- Add the fixes of the review of the load governor

- A governor whose engine went without telling it stops at its next tick

- A timing change while the engine stands starts no clock; a reset of the stream's counters counts no xruns backwards

- The sample of a period and the stolen units of the last minute in functions of their own; the clocks of the Android cores too

- sysctlString keeps a terminator; the system properties of Android through one lookup of libc

- The config names its broken assertion; AudLoadSample.fromJson after its constructor

- The API of the governor and the inputs of the start budgets in the READMEs; the web fixture uses the governor

## 0.4.1 - 2026-10-13

### Added

- Add an example that resolves outside a full ticket
- The example overrides only aud_audio; the family comes from its git tags and pub.dev
- The example depends on aud_audio_midi ^0.1.0

## 0.4.0 - 2026-10-12

### Added

- Add engine extensions and the engine's timing

- AudEngineExtension: the engine tells an extension when it started, stops, when its timing starts again and, before it disposes the graph, synchronously

- AudEngine.timing: the graph's timing of the last block for the control side (midi-003)

- The example resolves core and the sampler through their tags and asks for aud_dsp_sampler ^0.2.0

- Add the MIDI keyboard page of the example

- MidiPage: a MIDI port plays the sampler through aud_audio_midi, with a port picker, the activity, the timing and the input to output time

- integration_test/midi_test.dart: a recorded performance through a source of the app, with warm-up and measured minutes; midi_paths_test.dart measures the native and the Dart paths (midi-002)

- Android: the loopback device of aud_midi_android and the Bluetooth permissions; iOS: Bluetooth, local network and background audio

- aud_midi_standard from pub.dev; the example runs against the ticket's checkouts

- Add the guided keyboard test and the path measurement

- integration_test/midi_keyboard_test.dart: a person plays a keyboard, then the hot-plug with a held chord and Bluetooth MIDI, guided by prompts on the page

- midi_paths_test.dart measures the native and the Dart paths with sources of its own at one C

- The MIDI page: a Bluetooth MIDI dialog, a prompt banner, C and m of the input

- Add Bluetooth and permissions to the MIDI page

- The page uses Apple's picker on iOS and asks Android for the Bluetooth scan permission

- The guided keyboard test forwards touches and can skip its phases

- README for extensions, timing and the MIDI page

- Add permission_handler 12 to the example

- Version 13 needs Android SDK platform 37

- Add aud_midi_standard from pub.dev to the example

- The example resolves aud_midi_standard from pub.dev instead of a sibling checkout

- Add review fixes of ticket 26

- Add independent constraints on the aud_midi packages

- Add review fixes of ticket 26

- dispose() stops a running engine first, so the extensions hear engineStopping before engineDisposing

- One helper tells the extensions that the engine started, stops or changed its timing

- Example: Bluetooth MIDI on Android needs the permissions to scan and to connect, or the location below Android 12

## 0.3.0 - 2026-10-12

### Added

- Add the sample cache budget and the sampler page

- AudEngineConfig.cacheBudget sets the sample cache budget of the process (lifecycle-002)

- AudEngineNumbers and the report: cacheBytes, cacheBudget, cacheTrimmed, loadsRunning, loadsFailed, loadTimeMaxNs

- The example: two pages on one engine, the oscillator and the SFZ sampler of aud_dsp_sampler with generated instruments, a multi-touch keyboard, sustain, modulation, load progress, a 64-voice test and an auto-play with an animated UI

- integration_test/sampler_test.dart measures the M1 budgets: load, 64 voices offline and live, command to sound, xruns

- The example reaches the sibling packages through pubspec_overrides.yaml

- Add the steady state of 64 voices to the sampler test

- The live measurement of 64 voices splits the block in which the notes start from the 2 s after it

- The test scrolls back to the start button before it stops the engine, as on a tablet

- Add the review fixes of the load numbers and the budget

- loadNumbers counts no load that ended with AUD_ERROR_CANCELLED as failed, also not one that a newer load replaced or whose node went

- AudEngineFfi sets the cache budget inside the open: a budget the graph refuses releases the session, the stream and the graph

- AudEngineConfig.cacheBudget cites lifecycle-002

- The tests compare the JSON of AudEngineNumbers as a whole and the cache numbers with the cache usage

- Add the review fixes of the sampler page and its test

- The volume slider waits for the sampler and covers the range of its parameter, -60 to +6 dB

- The load progress follows the running load; a load that a newer selection replaced no longer overwrites the page

- An error of the instrument picker shows on the page instead of escaping as an unhandled error

- Another isolate writes the instrument, once per app, so that the page opens without dropping frames

- engine_panel.dart shows the state, route, format, start button, numbers and report of both pages; the sampler page copies its report too

- instruments.dart holds the instruments; a test instrument whose envelope moved throws a StateError instead of playing unchanged

- The build of the sampler page is split, its private members come last, its numbers have names, the unused directory is gone

- The keyboard ends the notes its fingers still hold when it goes, has its landmarks and names its numbers

- sampler_test.dart checks that the offline instrument loaded and 64 voices sound, computes the budget once and plays the notes of the page

- AUD_WARMUP_SECONDS lets the auto-play warm the device up before the measured AUD_MEASURE_SECONDS; only the measured part counts

- The stale comment above flutter: in the pubspec of the example is gone

- Add the German README sections and the warm-up command

- README.de.md says what README.md says: the cache and load numbers, the cache budget through AudEngineConfig (lifecycle-002), the plan of ticket 25, the sampler in the code example and the two pages of the example

- README.md, README.de.md and example/README.md show the measuring command of sampler_test.dart with AUD_WARMUP_SECONDS

- example/README.md describes both pages and both integration tests

## 0.2.0 - 2026-10-09

### Changed

- Build the engine for iOS and Android
- Load the test package as a library of its own

### Fixed

- Fix the findings of the code review of the engine

## 0.1.0 - 2026-10-08

### Added

- Add the spike example app

## 0.0.2 - 2026-10-08

### Added

- Initial boilerplate

### Changed

- Record the gg commit state
- Set up GitHub repo settings and branch rules
- Update dev dependencies
