/// Configuration for PeekShield detection thresholds.
///
/// All angle values are in degrees. Adjust thresholds to tune
/// sensitivity vs false-positive rate.
class PeekConfig {
  /// Yaw (left-right rotation) threshold above which a peek is immediately
  /// declared regardless of enrollment. Default: 30.0°
  final double yawHardThreshold;

  /// Soft yaw threshold used when no enrollment exists to declare
  /// [PeekState.uncertain]. Default: 20.0°
  final double yawSoftThreshold;

  /// Pitch (up-down tilt) hard threshold. Default: 35.0°
  final double pitchHardThreshold;

  /// Soft pitch threshold for uncertain state (no enrollment). Default: 25.0°
  final double pitchSoftThreshold;

  /// How long (ms) to hold the blur after the last peek trigger clears.
  /// Prevents rapid flickering. Default: 800
  final int blurHoldMs;

  /// Cosine similarity minimum for enrolled face match.
  /// Values below this threshold → [PeekState.peeking]. Default: 0.55
  final double enrollMatchThreshold;

  /// How many seconds of no detected face before declaring [PeekState.clear]
  /// (owner put phone down). Default: 2.0
  final double noFaceClearSeconds;

  const PeekConfig({
    this.yawHardThreshold = 30.0,
    this.yawSoftThreshold = 20.0,
    this.pitchHardThreshold = 35.0,
    this.pitchSoftThreshold = 25.0,
    this.blurHoldMs = 800,
    this.enrollMatchThreshold = 0.55,
    this.noFaceClearSeconds = 2.0,
  });

  /// Preset for low sensitivity (fewer false positives, misses subtle peeks).
  factory PeekConfig.low() => const PeekConfig(
        yawHardThreshold: 40.0,
        yawSoftThreshold: 30.0,
        pitchHardThreshold: 45.0,
        pitchSoftThreshold: 35.0,
        blurHoldMs: 600,
        enrollMatchThreshold: 0.45,
      );

  /// Preset for high sensitivity (catches more peeks, may have false positives).
  factory PeekConfig.high() => const PeekConfig(
        yawHardThreshold: 20.0,
        yawSoftThreshold: 12.0,
        pitchHardThreshold: 25.0,
        pitchSoftThreshold: 18.0,
        blurHoldMs: 1000,
        enrollMatchThreshold: 0.65,
      );

  PeekConfig copyWith({
    double? yawHardThreshold,
    double? yawSoftThreshold,
    double? pitchHardThreshold,
    double? pitchSoftThreshold,
    int? blurHoldMs,
    double? enrollMatchThreshold,
    double? noFaceClearSeconds,
  }) {
    return PeekConfig(
      yawHardThreshold: yawHardThreshold ?? this.yawHardThreshold,
      yawSoftThreshold: yawSoftThreshold ?? this.yawSoftThreshold,
      pitchHardThreshold: pitchHardThreshold ?? this.pitchHardThreshold,
      pitchSoftThreshold: pitchSoftThreshold ?? this.pitchSoftThreshold,
      blurHoldMs: blurHoldMs ?? this.blurHoldMs,
      enrollMatchThreshold: enrollMatchThreshold ?? this.enrollMatchThreshold,
      noFaceClearSeconds: noFaceClearSeconds ?? this.noFaceClearSeconds,
    );
  }
}
