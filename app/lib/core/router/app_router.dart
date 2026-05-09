import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/biometric_gate.dart';
import '../../features/onboarding/enrollment_page.dart';
import '../../features/vault/credit_cards/credit_card_vault_page.dart';
import '../../features/vault/chat/chat_screen.dart';
import '../../features/vault/wallet/wallet_page.dart';
import '../../features/settings/settings_page.dart';
import '../providers/screen_capture_provider.dart';

// ── Route name constants ─────────────────────────────────────────────────────
class AppRoutes {
  AppRoutes._();
  static const String enrollment = '/enrollment';
  static const String vault = '/vault';
  static const String creditCards = '/vault/cards';
  static const String chat = '/vault/chat';
  static const String wallet = '/vault/wallet';
  static const String settings = '/settings';
}

// ── Router provider ──────────────────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.enrollment,
    routes: [
      GoRoute(
        path: AppRoutes.enrollment,
        builder: (context, state) => const EnrollmentPage(),
      ),
      GoRoute(
        path: AppRoutes.vault,
        builder: (context, state) => const BiometricGate(),
        routes: [
          GoRoute(
            path: 'cards',
            builder: (context, state) => const CreditCardVaultPage(),
          ),
          GoRoute(
            path: 'chat',
            builder: (context, state) => const ChatScreen(),
          ),
          GoRoute(
            path: 'wallet',
            builder: (context, state) => const WalletPage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
});
