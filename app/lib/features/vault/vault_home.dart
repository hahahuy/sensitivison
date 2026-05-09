import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// Vault home — navigation hub for credit cards, chat, and wallet vaults.
class VaultHome extends StatelessWidget {
  const VaultHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        title: const Text('PeekShield Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Vaults',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'All content is protected by peek detection.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _VaultCard(
              icon: Icons.credit_card_outlined,
              title: 'Credit Cards',
              subtitle: 'Store and access card numbers securely',
              color: AppTheme.accentBlue,
              onTap: () => context.push(AppRoutes.creditCards),
            ),
            const SizedBox(height: 16),
            _VaultCard(
              icon: Icons.chat_bubble_outline,
              title: 'Private Chat',
              subtitle: 'End-to-end encrypted message archive',
              color: AppTheme.accentGreen,
              onTap: () => context.push(AppRoutes.chat),
            ),
            const SizedBox(height: 16),
            _VaultCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Crypto Wallet',
              subtitle: 'Addresses, balances, and seed phrases',
              color: AppTheme.accentOrange,
              onTap: () => context.push(AppRoutes.wallet),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _VaultCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
