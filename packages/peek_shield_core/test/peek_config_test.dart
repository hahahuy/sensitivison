import 'package:flutter_test/flutter_test.dart';
import 'package:peek_shield_core/src/detection/peek_config.dart';

void main() {
  group('PeekConfig', () {
    test('default values are within reasonable range', () {
      const config = PeekConfig();
      expect(config.yawHardThreshold, 30.0);
      expect(config.yawSoftThreshold, 20.0);
      expect(config.pitchHardThreshold, 35.0);
      expect(config.pitchSoftThreshold, 25.0);
      expect(config.blurHoldMs, 800);
      expect(config.enrollMatchThreshold, 0.55);
      expect(config.noFaceClearSeconds, 2.0);
    });

    test('low preset has higher (more lenient) thresholds', () {
      final low = PeekConfig.low();
      const def = PeekConfig();
      expect(low.yawHardThreshold, greaterThan(def.yawHardThreshold));
      expect(low.pitchHardThreshold, greaterThan(def.pitchHardThreshold));
    });

    test('high preset has lower (more sensitive) thresholds', () {
      final high = PeekConfig.high();
      const def = PeekConfig();
      expect(high.yawHardThreshold, lessThan(def.yawHardThreshold));
      expect(high.pitchHardThreshold, lessThan(def.pitchHardThreshold));
    });

    test('copyWith overrides only specified fields', () {
      const config = PeekConfig();
      final modified = config.copyWith(blurHoldMs: 1200);
      expect(modified.blurHoldMs, 1200);
      expect(modified.yawHardThreshold, config.yawHardThreshold);
    });
  });
}
