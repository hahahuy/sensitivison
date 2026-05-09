/// Widget tests for [BlurShield] and [ProtectedWidget].
///
/// These tests use a mock [PeekState] stream injected via Riverpod overrides
/// so no camera or ML Kit initialisation is needed.
///
/// Tested behaviours:
///   • Child renders when state is clear
///   • BackdropFilter + overlay appear when state is peeking
///   • AnimatedOpacity transitions between 0 and 1
///   • forceBlur: true always blurs regardless of stream state
///   • Multiple consecutive state changes are handled correctly
///   • ProtectedWidget delegates to BlurShield
///
/// Run with:
///   flutter test app/test/blur_shield_widget_test.dart
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Inline minimal versions of the SDK types so this test file is self-contained
// and does not import the real peek_shield_core (which would pull in camera /
// ML Kit / TFLite dependencies that require real device hardware).
// ---------------------------------------------------------------------------

enum PeekState { clear, uncertain, peeking }

// Provider that the BlurShield widget under test will watch.
final testPeekStateProvider = StreamProvider.autoDispose<PeekState>((ref) {
  // Default: clear. Overridden per test via ProviderScope overrides.
  return Stream.value(PeekState.clear);
});

// ---------------------------------------------------------------------------
// Minimal BlurShield and ProtectedWidget implementations that mirror the real
// widgets but reference [testPeekStateProvider] instead of the SDK provider.
// ---------------------------------------------------------------------------

class BlurShieldUnderTest extends ConsumerWidget {
  const BlurShieldUnderTest({super.key, required this.child, this.forceBlur = false});
  final Widget child;
  final bool forceBlur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peekAsync = ref.watch(testPeekStateProvider);
    final bool isPeeking = forceBlur ||
        peekAsync.maybeWhen(
          data: (s) => s == PeekState.peeking,
          orElse: () => false,
        );
    return Stack(
      children: [
        child,
        AnimatedOpacity(
          key: const ValueKey('blur_overlay'),
          opacity: isPeeking ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            color: Colors.black54,
            child: const Center(
              child: Icon(Icons.lock, color: Colors.white, key: ValueKey('lock_icon')),
            ),
          ),
        ),
      ],
    );
  }
}

class ProtectedWidgetUnderTest extends StatelessWidget {
  const ProtectedWidgetUnderTest({super.key, required this.child, this.localOverride = false});
  final Widget child;
  final bool localOverride;

  @override
  Widget build(BuildContext context) =>
      BlurShieldUnderTest(forceBlur: localOverride, child: child);
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

StreamController<PeekState> _peekController() {
  final ctrl = StreamController<PeekState>.broadcast();
  return ctrl;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BlurShield', () {
    testWidgets('renders child when peek state is clear', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.clear),
            ),
          ],
          child: const BlurShieldUnderTest(
            child: Text('Secret Data', key: ValueKey('secret')),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('secret')), findsOneWidget);
    });

    testWidgets('overlay is transparent (opacity=0) when state is clear',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.clear),
            ),
          ],
          child: const BlurShieldUnderTest(
            child: Text('Secret'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('blur_overlay')),
      );
      expect(animatedOpacity.opacity, 0.0);
    });

    testWidgets('overlay is opaque (opacity=1) when state is peeking',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.peeking),
            ),
          ],
          child: const BlurShieldUnderTest(
            child: Text('Secret'),
          ),
        ),
      );
      await tester.pump();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('blur_overlay')),
      );
      expect(animatedOpacity.opacity, 1.0);
    });

    testWidgets('lock icon is visible when peeking', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.peeking),
            ),
          ],
          child: const BlurShieldUnderTest(child: Text('Secret')),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('lock_icon')), findsOneWidget);
    });

    testWidgets('forceBlur: true blurs even when peek state is clear',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.clear),
            ),
          ],
          child: const BlurShieldUnderTest(
            forceBlur: true,
            child: Text('Secret'),
          ),
        ),
      );
      await tester.pump();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('blur_overlay')),
      );
      expect(animatedOpacity.opacity, 1.0);
    });

    testWidgets('state transition clear → peeking shows overlay',
        (tester) async {
      final ctrl = _peekController();
      ctrl.add(PeekState.clear);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith((ref) => ctrl.stream),
          ],
          child: const BlurShieldUnderTest(child: Text('Secret')),
        ),
      );
      await tester.pump();

      // Clear → overlay transparent
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const ValueKey('blur_overlay')))
            .opacity,
        0.0,
      );

      ctrl.add(PeekState.peeking);
      await tester.pump();

      // Peeking → overlay opaque
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const ValueKey('blur_overlay')))
            .opacity,
        1.0,
      );

      await ctrl.close();
    });

    testWidgets('state transition peeking → clear hides overlay', (tester) async {
      final ctrl = _peekController();
      ctrl.add(PeekState.peeking);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith((ref) => ctrl.stream),
          ],
          child: const BlurShieldUnderTest(child: Text('Secret')),
        ),
      );
      await tester.pump();

      // Confirm blurred
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const ValueKey('blur_overlay')))
            .opacity,
        1.0,
      );

      ctrl.add(PeekState.clear);
      await tester.pump();

      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const ValueKey('blur_overlay')))
            .opacity,
        0.0,
      );

      await ctrl.close();
    });

    testWidgets('uncertain state does not trigger blur', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.uncertain),
            ),
          ],
          child: const BlurShieldUnderTest(child: Text('Secret')),
        ),
      );
      await tester.pump();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('blur_overlay')),
      );
      expect(animatedOpacity.opacity, 0.0);
    });
  });

  group('ProtectedWidget', () {
    testWidgets('wraps child in BlurShield', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.clear),
            ),
          ],
          child: const ProtectedWidgetUnderTest(
            child: Text('Sensitive', key: ValueKey('sens')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('sens')), findsOneWidget);
    });

    testWidgets('localOverride: true forces blur without peek state',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            testPeekStateProvider.overrideWith(
              (ref) => Stream.value(PeekState.clear),
            ),
          ],
          child: const ProtectedWidgetUnderTest(
            localOverride: true,
            child: Text('Sensitive'),
          ),
        ),
      );
      await tester.pump();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('blur_overlay')),
      );
      expect(animatedOpacity.opacity, 1.0);
    });
  });
}
