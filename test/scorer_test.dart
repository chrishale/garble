import 'package:flutter_test/flutter_test.dart';
import 'package:garble/data/levels.dart';
import 'package:garble/services/scorer.dart';

void main() {
  const scorer = Scorer();

  test('word score – 1-pop bonus applies', () {
    expect(Scorer.wordScore(5, 1), 5 * 10 + 5 * 10);
    expect(Scorer.wordScore(4, 1), 4 * 10 + 4 * 10);
  });

  test('word score – multi-pop gives only base', () {
    expect(Scorer.wordScore(5, 2), 5 * 10);
    expect(Scorer.wordScore(5, 3), 5 * 10);
  });

  test('every level has a reachable word and positive max score', () {
    for (final level in kLevels) {
      final full = (1 << level.garble.length) - 1;
      expect(
        scorer.hasReachableWord(level.garble, full, level.words),
        isTrue,
        reason: '${level.garble} should have at least one reachable word',
      );
      final m = scorer.maxScore(level.garble, level.words);
      expect(m, greaterThan(0), reason: '${level.garble} max score');
      level.maxScore = m;
      final path = scorer.bestPath(level.garble, level.words);
      // ignore: avoid_print
      print('${level.garble}: max=$m  path: ${[level.garble, ...path].join(" → ")}');
    }
  });
}
