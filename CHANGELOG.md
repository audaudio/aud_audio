# Changelog

## Unreleased

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
