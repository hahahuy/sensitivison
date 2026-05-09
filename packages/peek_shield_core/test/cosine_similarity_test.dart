import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// Extracted cosine similarity logic for unit testing without ML dependencies
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = sqrt(normA) * sqrt(normB);
  return denom == 0 ? 0.0 : dot / denom;
}

List<double> l2normalize(List<double> vec) {
  final norm = sqrt(vec.fold(0.0, (sum, v) => sum + v * v));
  if (norm == 0) return vec;
  return vec.map((v) => v / norm).toList();
}

void main() {
  group('cosineSimilarity', () {
    test('identical vectors → similarity = 1.0', () {
      final v = [0.5, 0.3, 0.8, 0.1];
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors → similarity ≈ 0.0', () {
      final a = [1.0, 0.0];
      final b = [0.0, 1.0];
      expect(cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('opposite vectors → similarity = -1.0', () {
      final a = [1.0, 0.0];
      final b = [-1.0, 0.0];
      expect(cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('similar but not identical vectors above match threshold', () {
      // Two embeddings that represent the same person should have sim > 0.55
      final base = l2normalize(List.generate(128, (i) => sin(i.toDouble())));
      // Add slight noise
      final rng = Random(42);
      final noisy = l2normalize(
        base.map((v) => v + (rng.nextDouble() - 0.5) * 0.05).toList(),
      );
      final sim = cosineSimilarity(base, noisy);
      expect(sim, greaterThan(0.55));
    });

    test('random unrelated vectors below match threshold', () {
      final rng = Random(123);
      final a = l2normalize(List.generate(128, (_) => rng.nextDouble()));
      final rng2 = Random(456);
      final b = l2normalize(List.generate(128, (_) => rng2.nextDouble()));
      final sim = cosineSimilarity(a, b);
      // Unrelated embeddings should have low similarity
      expect(sim, lessThan(0.55));
    });
  });

  group('l2normalize', () {
    test('normalized vector has unit length', () {
      final v = [3.0, 4.0];
      final n = l2normalize(v);
      final length = sqrt(n.fold(0.0, (s, x) => s + x * x));
      expect(length, closeTo(1.0, 1e-6));
    });

    test('zero vector returns zero vector (no division by zero)', () {
      final v = [0.0, 0.0, 0.0];
      final n = l2normalize(v);
      expect(n.every((x) => x == 0.0), isTrue);
    });
  });
}
