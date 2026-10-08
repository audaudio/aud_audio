# aud_audio

The Audanika Audio Engine: a Flutter audio graph defined in Dart and rendered in C++ on iOS, Android, macOS, Windows, Linux and Web.

Part of the Audanika Audio Engine; planned in [aud_audio_pm](https://github.com/audaudio/aud_audio_pm).

## The example app (ticket 5)

`example/` is the spike app of the mobile foundation: the reference sine
of `aud_audio_graph` through the tremolo of `aud_dsp_effects`, the legacy
sine sample set of the Audanika app through the sfizz sampler of
`aud_dsp_sampler` (converted to SFZ at start-up by `lib/legacy_sfz.dart`),
a sustained test that plays random notes, and a measurement panel with
the callback period, the time spent in the callback, the command latency
and the render time of the engine. Until ticket S4 gives this package its
`Engine`, the app depends on graph, io and the DSP packages directly.

```bash
cd example
flutter run -d <ios simulator | android emulator | macos>
```
