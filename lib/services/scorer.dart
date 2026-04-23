import 'dart:math' as math;

class Scorer {
  const Scorer();

  /// Points awarded for a banked word.
  ///   base  = length * 10
  ///   bonus = length * 10 when reached with exactly 1 pop since the last
  ///           bank (or since the start).
  static int wordScore(int wordLength, int popsSinceLastBank) {
    final base = wordLength * 10;
    final bonus = popsSinceLastBank == 1 ? wordLength * 10 : 0;
    return base + bonus;
  }

  /// The theoretical maximum score reachable from [garble] when the allowed
  /// English words are [words].
  int maxScore(String garble, Set<String> words) {
    final n = garble.length;
    final fullMask = (1 << n) - 1;
    final memo = <int, int>{};

    int solve(int mask, int popsCap) {
      final key = (mask << 2) | popsCap;
      final cached = memo[key];
      if (cached != null) return cached;

      var best = 0;
      for (var i = 0; i < n; i++) {
        final bit = 1 << i;
        if ((mask & bit) == 0) continue;
        final newMask = mask & ~bit;
        if (newMask == 0) continue;

        final subseq = _subseq(garble, newMask);
        final newPopsCap = popsCap >= 2 ? 2 : popsCap + 1;

        int score;
        if (words.contains(subseq)) {
          final bonusApplies = newPopsCap == 1;
          final gained = subseq.length * 10 + (bonusApplies ? subseq.length * 10 : 0);
          score = gained + solve(newMask, 0);
        } else {
          score = solve(newMask, newPopsCap);
        }
        if (score > best) best = score;
      }
      memo[key] = best;
      return best;
    }

    return solve(fullMask, 0);
  }

  /// Reconstructs one path through [garble] that achieves the max score
  /// using [words] as the allowed dictionary.
  List<String> bestPath(String garble, Set<String> words) {
    final n = garble.length;
    final fullMask = (1 << n) - 1;
    final memo = <int, int>{};

    int solve(int mask, int popsCap) {
      final key = (mask << 2) | popsCap;
      final cached = memo[key];
      if (cached != null) return cached;

      var best = 0;
      for (var i = 0; i < n; i++) {
        final bit = 1 << i;
        if ((mask & bit) == 0) continue;
        final newMask = mask & ~bit;
        if (newMask == 0) continue;

        final subseq = _subseq(garble, newMask);
        final newPopsCap = popsCap >= 2 ? 2 : popsCap + 1;

        int score;
        if (words.contains(subseq)) {
          final bonusApplies = newPopsCap == 1;
          final gained = subseq.length * 10 + (bonusApplies ? subseq.length * 10 : 0);
          score = gained + solve(newMask, 0);
        } else {
          score = solve(newMask, newPopsCap);
        }
        if (score > best) best = score;
      }
      memo[key] = best;
      return best;
    }

    solve(fullMask, 0);

    final path = <String>[];
    var mask = fullMask;
    var popsCap = 0;
    while (true) {
      final target = memo[(mask << 2) | popsCap] ?? 0;
      if (target == 0) break;
      var moved = false;
      for (var i = 0; i < n; i++) {
        final bit = 1 << i;
        if ((mask & bit) == 0) continue;
        final newMask = mask & ~bit;
        if (newMask == 0) continue;

        final subseq = _subseq(garble, newMask);
        final newPopsCap = popsCap >= 2 ? 2 : popsCap + 1;

        int score;
        int nextPopsCap;
        bool banked;
        if (words.contains(subseq)) {
          final bonusApplies = newPopsCap == 1;
          final gained = subseq.length * 10 + (bonusApplies ? subseq.length * 10 : 0);
          score = gained + (memo[(newMask << 2) | 0] ?? 0);
          nextPopsCap = 0;
          banked = true;
        } else {
          score = memo[(newMask << 2) | newPopsCap] ?? 0;
          nextPopsCap = newPopsCap;
          banked = false;
        }

        if (score == target) {
          if (banked) path.add(subseq);
          mask = newMask;
          popsCap = nextPopsCap;
          moved = true;
          break;
        }
      }
      if (!moved) break;
    }
    return path;
  }

  /// Does any non-empty proper subset of [mask] form a word in [words]?
  bool hasReachableWord(String garble, int mask, Set<String> words) {
    var sub = (mask - 1) & mask;
    while (sub > 0) {
      final s = _subseq(garble, sub);
      if (words.contains(s)) return true;
      sub = (sub - 1) & mask;
    }
    return false;
  }

  /// Compute max score reachable from a live in-progress state.
  int maxScoreFrom(String garble, Set<String> words, int mask, int popsSinceLastBank) {
    final n = garble.length;
    final memo = <int, int>{};

    int solve(int m, int popsCap) {
      final key = (m << 2) | popsCap;
      final cached = memo[key];
      if (cached != null) return cached;

      var best = 0;
      for (var i = 0; i < n; i++) {
        final bit = 1 << i;
        if ((m & bit) == 0) continue;
        final newMask = m & ~bit;
        if (newMask == 0) continue;

        final subseq = _subseq(garble, newMask);
        final newPopsCap = popsCap >= 2 ? 2 : popsCap + 1;

        int score;
        if (words.contains(subseq)) {
          final bonusApplies = newPopsCap == 1;
          final gained = subseq.length * 10 + (bonusApplies ? subseq.length * 10 : 0);
          score = gained + solve(newMask, 0);
        } else {
          score = solve(newMask, newPopsCap);
        }
        if (score > best) best = score;
      }
      memo[key] = best;
      return best;
    }

    final popsCap = math.min(popsSinceLastBank, 2);
    return solve(mask, popsCap);
  }

  static String _subseq(String garble, int mask) {
    final n = garble.length;
    final sb = StringBuffer();
    for (var j = 0; j < n; j++) {
      if ((mask & (1 << j)) != 0) sb.write(garble[j]);
    }
    return sb.toString();
  }
}
