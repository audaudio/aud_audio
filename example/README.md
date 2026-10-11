# aud_audio_example

Two pages on one `AudEngine`, on iOS and Android:

- Oscillator: oscillator -> filter -> output on the reference nodes of
  `aud_audio_graph` with frequency and cutoff, and the command-to-sound
  latency
- Sampler: the SFZ sampler of `aud_dsp_sampler` with three instruments
  generated on the device, a multi-touch keyboard, sustain, modulation and
  volume, the load and its progress, a test of 64 voices and an auto-play
  with an animated UI

Both pages start and stop the engine and show its state, route, format and
numbers, with a report to copy.

```bash
flutter run -d <device>
flutter test integration_test/engine_test.dart -d <device> \
  --dart-define=AUD_MEASURE_SECONDS=600
flutter test integration_test/sampler_test.dart -d <device> \
  --dart-define=AUD_WARMUP_SECONDS=1200 \
  --dart-define=AUD_MEASURE_SECONDS=600 --dart-define=AUD_ASSERT_BUDGETS=true
```

`engine_test.dart` plays the oscillator for `AUD_MEASURE_SECONDS` and
prints the report. `sampler_test.dart` measures the M1 budgets of ticket
17: the load, 64 voices offline and live, command to sound, and the xruns
of the auto-play. `AUD_WARMUP_SECONDS` (default 0) lets the auto-play warm
the device up before the measured `AUD_MEASURE_SECONDS`; only the measured
part counts. `AUD_ASSERT_BUDGETS=true` turns the budgets into
expectations.
