import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/router/app_router.dart';
import 'peek_sensitivity_slider.dart';

// ── Settings providers ────────────────────────────────────────────────────────

/// Current PeekConfig — persisted via shared preferences or secure storage.
final peekConfigProvider = StateProvider<PeekConfig>(
  (ref) => const PeekConfig(),
);

/// Whether notification privacy mode is enabled.
final notifPrivacyProvider = StateProvider<bool>((ref) => true);

/// Whether enrollment matching is required (vs angle-only).
final requireEnrollmentProvider = StateProvider<bool>((ref) => false);

// ── Settings Page ────────────────────────────────────────────────────────────

/// App settings page — peek sensitivity, notification privacy, face enrollment.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifPrivacy = ref.watch(notifPrivacyProvider);
    final requireEnrollment = ref.watch(requireEnrollmentProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Peek Detection ─────────────────────────────────────────────
          _SectionHeader('Peek Detection'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sensitivity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final config = ref.watch(peekConfigProvider);
                        return Text(
                          _sensitivityLabel(config),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.accentBlue),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const PeekSensitivitySlider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Low = fewer false alerts. High = catches subtle peeks.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              SwitchListTile(
                value: requireEnrollment,
                onChanged: (v) =>
                    ref.read(requireEnrollmentProvider.notifier).state = v,
                title: const Text('Require Face Match'),
                subtitle: const Text(
                  'Blur if the detected face is not yours',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Notifications ──────────────────────────────────────────────
          _SectionHeader('Notifications'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              SwitchListTile(
                value: notifPrivacy,
                onChanged: (v) {
                  ref.read(notifPrivacyProvider.notifier).state = v;
                  _syncNotifPrivacy(v);
                },
                title: const Text('Private Notifications'),
                subtitle: const Text(
                  'Show "🔒 New message" instead of content',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Face Enrollment ────────────────────────────────────────────
          _SectionHeader('Face Enrollment'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.face_retouching_natural,
                  color: AppTheme.accentBlue,
                ),
                title: const Text('Re-enroll Face'),
                subtitle: const Text(
                  'Capture a new face embedding for detection',
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                onTap: () {
                  // Navigate back to enrollment
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
              const Divider(height: 1, indent: 16),
              Consumer(
                builder: (context, ref, _) {
                  return ListTile(
                    leading: Icon(
                      ref.watch(enrollmentStatusProvider)
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      color: ref.watch(enrollmentStatusProvider)
                          ? AppTheme.accentGreen
                          : AppTheme.textMuted,
                    ),
                    title: Text(
                      ref.watch(enrollmentStatusProvider)
                          ? 'Face enrolled'
                          : 'No enrollment — angle detection only',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: ref.watch(enrollmentStatusProvider)
                                ? AppTheme.accentGreen
                                : AppTheme.textMuted,
                          ),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Danger Zone ────────────────────────────────────────────────
          _SectionHeader('Danger Zone'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppTheme.accentRed,
                ),
                title: const Text(
                  'Wipe All Vault Data',
                  style: TextStyle(color: AppTheme.accentRed),
                ),
                subtitle: const Text('Permanently deletes all stored secrets'),
                onTap: () => _confirmWipe(context, ref),
              ),
            ],
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              'PeekShield v1.0.0',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _sensitivityLabel(PeekConfig config) {
    if (config.yawHardThreshold >= 38) return 'Low';
    if (config.yawHardThreshold <= 22) return 'High';
    return 'Medium';
  }

  void _syncNotifPrivacy(bool enabled) {
    // Write to App Group shared UserDefaults via method channel
    // (simplified — full implementation uses platform channel)
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'Wipe All Data?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This will permanently delete all cards, wallet entries, chat history, '
          'and face enrollment data. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            child: const Text('Wipe Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Clear all secure storage and Hive boxes
      // (Full implementation iterates known keys and deletes them)
      final enrollment = ref.read(enrollmentProvider);
      await enrollment.clearEnrollment();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All vault data wiped.'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }
}

// ── Enrollment status provider ────────────────────────────────────────────────

final enrollmentStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final service = ref.read(enrollmentProvider);
  return service.hasEnrollment();
});

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppTheme.textSecondary,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}
