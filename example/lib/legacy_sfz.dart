// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Turns a legacy Audanika sample set (`sampleInfo.xml` plus one WAV per
/// unity note) into an SFZ text for sfizz. Each sample covers the keys
/// nearest to its unity note; the loop points and the envelope of the
/// legacy sound carry over. The real conversion of the legacy presets is
/// ticket S9; this is the spike's minimal reading of the format.
class LegacySfz {
  /// Creates the converter for the XML of `sampleInfo.xml`.
  ///
  /// - [sampleInfoXml] the content of `sampleInfo.xml`
  /// - [lowestPitch] and [highestPitch] from the sample set's `info.xml`
  /// - [attackMs] and [releaseMs] from the legacy sound
  /// - [linearGain] from the legacy sound
  LegacySfz({
    required this.sampleInfoXml,
    this.lowestPitch = 28,
    this.highestPitch = 108,
    this.attackMs = 10,
    this.releaseMs = 100,
    this.linearGain = 1.0,
  });

  /// The content of `sampleInfo.xml`.
  final String sampleInfoXml;

  /// The lowest key the sample set covers.
  final int lowestPitch;

  /// The highest key the sample set covers.
  final int highestPitch;

  /// The attack of the legacy sound in milliseconds.
  final double attackMs;

  /// The release of the legacy sound in milliseconds.
  final double releaseMs;

  /// The linear gain of the legacy sound.
  final double linearGain;

  /// The samples of the set: file name, unity note, loop start and end.
  List<LegacySample> get samples {
    final pattern = RegExp(
      r'<SampleInfo\s+fileName="([^"]+)"[^>]*?loopEnd="(\d+)"[^>]*?'
      r'loopStart="(\d+)"[^>]*?midiUnityNote="(\d+)"',
    );
    final result = [
      for (final m in pattern.allMatches(sampleInfoXml))
        LegacySample(
          fileName: m.group(1)!,
          unityNote: int.parse(m.group(4)!),
          loopStart: int.parse(m.group(3)!),
          loopEnd: int.parse(m.group(2)!),
        ),
    ];
    result.sort((a, b) => a.unityNote.compareTo(b.unityNote));
    return result;
  }

  /// The SFZ text; sample paths are relative to the virtual SFZ path.
  String toSfz() {
    final sorted = samples;
    final buffer = StringBuffer('<control>\n<global>\n')
      ..writeln('ampeg_attack=${(attackMs / 1000).toStringAsFixed(3)}')
      ..writeln('ampeg_release=${(releaseMs / 1000).toStringAsFixed(3)}')
      ..writeln('volume=${_decibels(linearGain).toStringAsFixed(2)}')
      ..writeln('loop_mode=loop_continuous');
    for (var i = 0; i < sorted.length; i++) {
      final sample = sorted[i];
      final low = i == 0
          ? lowestPitch
          : (sorted[i - 1].unityNote + sample.unityNote) ~/ 2 + 1;
      final high = i == sorted.length - 1
          ? highestPitch
          : (sample.unityNote + sorted[i + 1].unityNote) ~/ 2;
      buffer
        ..writeln('<region>')
        ..writeln('sample=${sample.fileName}')
        ..writeln('pitch_keycenter=${sample.unityNote}')
        ..writeln('lokey=$low hikey=$high')
        ..writeln('loop_start=${sample.loopStart} loop_end=${sample.loopEnd}');
    }
    return buffer.toString();
  }

  static double _decibels(double linear) =>
      linear <= 0 ? -60 : 20 * _log10(linear);

  static double _log10(double x) => _ln(x) / _ln(10);

  static double _ln(double x) {
    // Natural logarithm without dart:math, to keep this file dependency free.
    var result = 0.0;
    var value = x;
    while (value > 2) {
      value /= 2;
      result += 0.6931471805599453;
    }
    while (value < 0.5) {
      value *= 2;
      result -= 0.6931471805599453;
    }
    final y = (value - 1) / (value + 1);
    var term = y;
    var sum = 0.0;
    for (var n = 1; n < 60; n += 2) {
      sum += term / n;
      term *= y * y;
    }
    return result + 2 * sum;
  }
}

/// One sample of a legacy sample set.
class LegacySample {
  /// Creates the description of a sample.
  const LegacySample({
    required this.fileName,
    required this.unityNote,
    required this.loopStart,
    required this.loopEnd,
  });

  /// The WAV file name, relative to the `44kHz` directory.
  final String fileName;

  /// The MIDI note the sample was recorded at.
  final int unityNote;

  /// The loop start in frames.
  final int loopStart;

  /// The loop end in frames.
  final int loopEnd;
}
