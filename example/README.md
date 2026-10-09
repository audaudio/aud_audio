# aud_audio_example

Oscillator -> filter -> output on the reference nodes of
`aud_audio_graph`, played by `AudEngine` on iOS and Android: frequency and
cutoff, start and stop, the current route, the numbers of the engine and a
report to copy.

```bash
flutter run -d <device>
flutter test integration_test/engine_test.dart -d <device> \
  --dart-define=AUD_MEASURE_SECONDS=600
```
