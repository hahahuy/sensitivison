import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import 'settings_page.dart';

/// Three-position sensitivity slider that maps to [PeekConfig] presets.
///
/// Low (0) → [PeekConfig.low()]
/// Medium (1) → [PeekConfig()] (default)
/// High (2) → [PeekConfig.high()]
class PeekSensitivitySlider extends ConsumerWidget {
  const PeekSensitivitySlider({super.key});

  static const _labels = ['Low', 'Medium', 'High'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(peekConfigProvider);
    final sliderValue = _configToSlider(config);

    return Column(
      children: [
        Slider(
          value: sliderValue,
          min: 0,
          max: 2,
          divisions: 2,
          onChanged: (v) {
            ref.read(peekConfigProvider.notifier).state = _sliderToConfig(v);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _labels
                .map(
                  (l) => Text(
                    l,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: _labels[sliderValue.round()] == l
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  double _configToSlider(PeekConfig config) {
    if (config.yawHardThreshold >= 38) return 0; // Low
    if (config.yawHardThreshold <= 22) return 2; // High
    return 1; // Medium
  }

  PeekConfig _sliderToConfig(double v) {
    switch (v.round()) {
      case 0:
        return PeekConfig.low();
      case 2:
        return PeekConfig.high();
      default:
        return const PeekConfig();
    }
  }
}
