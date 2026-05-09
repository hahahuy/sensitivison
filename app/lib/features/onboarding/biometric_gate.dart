import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../vault/vault_home.dart';

/// Biometric authentication gate shown on app resume from background.
///
/// Uses [local_auth] to verify the device owner before revealing vault content.
/// On success renders [VaultHome]; on failure shows an error and retry option.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key});

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _authenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() => _unlocked = false);
    }
    if (state == AppLifecycleState.resumed && !_unlocked) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _errorMessage = null;
    });

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheck && !isDeviceSupported) {
        // Device has no biometrics — allow through
        setState(() => _unlocked = true);
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access your PeekShield vault',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allow passcode fallback
          stickyAuth: true,
        ),
      );

      if (!mounted) return;
      setState(() => _unlocked = authenticated);
      if (!authenticated) {
        setState(() => _errorMessage = 'Authentication failed. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Authentication error: $e');
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const VaultHome();

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 72,
                  color: AppTheme.accentBlue,
                ),
                const SizedBox(height: 24),
                Text(
                  'PeekShield Vault',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate to access your sensitive data.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.accentRed,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (_authenticating)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock Vault'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
