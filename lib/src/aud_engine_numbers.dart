// @license
// Copyright (c) Audanika. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The numbers S24 starts with (ticket 22): render time, xruns and
/// command-to-sound latency, read from the graph statistics, the stream
/// counters and the measurements of `AudEngine.measureCommandToSound`.
class AudEngineNumbers {
  /// Creates the numbers.
  const AudEngineNumbers({
    required this.sampleRate,
    required this.bufferFrames,
    required this.blocksRendered,
    required this.renderTimeMaxNs,
    required this.renderTimeMeanNs,
    required this.callbacks,
    required this.callbackTimeMaxNs,
    required this.callbackTimeMeanNs,
    required this.xruns,
    required this.lateCallbacks,
    required this.recoveries,
    required this.recoveryTimeMaxNs,
    required this.outputLatencyFrames,
    this.commandToSoundNs = const [],
  });

  // ...........................................................................
  /// The sample rate of the stream.
  final double sampleRate;

  /// The device buffer in frames.
  final int bufferFrames;

  /// The blocks the graph rendered.
  final int blocksRendered;

  /// The longest render of a block, in nanoseconds.
  final int renderTimeMaxNs;

  /// The mean render of a block, in nanoseconds.
  final double renderTimeMeanNs;

  /// The callbacks of the device.
  final int callbacks;

  /// The longest callback, in nanoseconds.
  final int callbackTimeMaxNs;

  /// The mean callback, in nanoseconds.
  final double callbackTimeMeanNs;

  /// Underruns and overruns the device reported.
  final int xruns;

  /// Callbacks that came later than their period allows.
  final int lateCallbacks;

  /// Recoveries of a lost device.
  final int recoveries;

  /// The longest recovery, in nanoseconds.
  final int recoveryTimeMaxNs;

  /// The output latency the stream reports, in frames.
  final int outputLatencyFrames;

  /// The command-to-sound latencies measured, in nanoseconds: from the host
  /// time of a command to the presentation time of the first block that
  /// carries it.
  final List<int> commandToSoundNs;

  // ...........................................................................
  /// The shortest command-to-sound latency, or null without a measurement.
  int? get commandToSoundMinNs => commandToSoundNs.isEmpty
      ? null
      : commandToSoundNs.reduce((a, b) => a < b ? a : b);

  /// The longest command-to-sound latency, or null without a measurement.
  int? get commandToSoundMaxNs => commandToSoundNs.isEmpty
      ? null
      : commandToSoundNs.reduce((a, b) => a > b ? a : b);

  /// The mean command-to-sound latency, or null without a measurement.
  double? get commandToSoundMeanNs => commandToSoundNs.isEmpty
      ? null
      : commandToSoundNs.reduce((a, b) => a + b) / commandToSoundNs.length;

  /// The numbers as JSON, for the report and later for `aud_audio_bench`.
  Map<String, Object?> toJson() => {
    'sampleRate': sampleRate,
    'bufferFrames': bufferFrames,
    'blocksRendered': blocksRendered,
    'renderTimeMaxNs': renderTimeMaxNs,
    'renderTimeMeanNs': renderTimeMeanNs.round(),
    'callbacks': callbacks,
    'callbackTimeMaxNs': callbackTimeMaxNs,
    'callbackTimeMeanNs': callbackTimeMeanNs.round(),
    'xruns': xruns,
    'lateCallbacks': lateCallbacks,
    'recoveries': recoveries,
    'recoveryTimeMaxNs': recoveryTimeMaxNs,
    'outputLatencyFrames': outputLatencyFrames,
    'commandToSoundNs': commandToSoundNs,
    'commandToSoundMinNs': commandToSoundMinNs,
    'commandToSoundMeanNs': commandToSoundMeanNs?.round(),
    'commandToSoundMaxNs': commandToSoundMaxNs,
  };

  @override
  String toString() => 'AudEngineNumbers(${toJson()})';
}
