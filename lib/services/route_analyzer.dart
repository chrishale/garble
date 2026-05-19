import 'dart:math' as math;

import 'scorer.dart';

/// A single step in a route (one word banked).
class RouteStep {
  final String word;
  final int popsSinceLastBank;
  final int score;
  final int mask;

  const RouteStep({
    required this.word,
    required this.popsSinceLastBank,
    required this.score,
    required this.mask,
  });

  int get baseScore => word.length * 10;
  int get bonusScore => popsSinceLastBank == 1 ? word.length * 10 : 0;
  bool get hasBonus => popsSinceLastBank == 1;
}

/// A complete route through a puzzle (sequence of banked words).
class Route {
  final List<RouteStep> steps;

  Route(this.steps);

  int get totalScore => steps.fold(0, (sum, s) => sum + s.score);

  int get totalPops => steps.fold(0, (sum, s) => sum + s.popsSinceLastBank);

  double get averagePops =>
      steps.isEmpty ? 0.0 : totalPops / steps.length;

  int get wordCount => steps.length;

  List<String> get words => steps.map((s) => s.word).toList();

  int get bonusCount => steps.where((s) => s.hasBonus).length;
}

/// Results of analyzing all routes through a puzzle.
class RouteAnalysis {
  final String garble;
  final Set<String> validWords;
  final List<Route> routes;
  final int maxScore;
  final bool limitReached;

  RouteAnalysis({
    required this.garble,
    required this.validWords,
    required this.routes,
    required this.maxScore,
    required this.limitReached,
  });

  List<Route> get maxScoreRoutes =>
      routes.where((r) => r.totalScore == maxScore).toList();

  double get averageScore => routes.isEmpty
      ? 0.0
      : routes.fold(0, (sum, r) => sum + r.totalScore) / routes.length;

  Map<int, int> get scoreDistribution {
    final dist = <int, int>{};
    for (final route in routes) {
      dist[route.totalScore] = (dist[route.totalScore] ?? 0) + 1;
    }
    return dist;
  }
}

/// Analyzes all possible routes through a Garble puzzle.
class RouteAnalyzer {
  final Scorer _scorer;

  const RouteAnalyzer([this._scorer = const Scorer()]);

  /// Enumerate routes through a garble puzzle.
  ///
  /// By default, only enumerates routes achieving max score (uses pruning).
  /// Set [maxScoreOnly] to false to enumerate all routes.
  /// Use [limit] to cap the number of routes returned.
  RouteAnalysis analyze(
    String garble,
    Set<String> words, {
    int? limit,
    bool maxScoreOnly = true,
  }) {
    final n = garble.length;
    final fullMask = (1 << n) - 1;

    // Compute max score using efficient DP
    final maxScore = _scorer.maxScore(garble, words);

    final routes = <Route>[];
    var limitReached = false;

    void explore(
      int mask,
      int popsSinceLastBank,
      List<RouteStep> currentPath,
      int currentScore,
    ) {
      // Check limit
      if (limit != null && routes.length >= limit) {
        limitReached = true;
        return;
      }

      // Game over: all letters popped
      if (mask == 0) {
        if (currentPath.isNotEmpty) {
          final route = Route(List.from(currentPath));
          if (!maxScoreOnly || route.totalScore == maxScore) {
            routes.add(route);
          }
        }
        return;
      }

      // Game over: no reachable words remain
      if (!_scorer.hasReachableWord(garble, mask, words)) {
        if (currentPath.isNotEmpty) {
          final route = Route(List.from(currentPath));
          if (!maxScoreOnly || route.totalScore == maxScore) {
            routes.add(route);
          }
        }
        return;
      }

      // Pruning for maxScoreOnly mode
      if (maxScoreOnly) {
        final popsCap = math.min(popsSinceLastBank, 2);
        final remaining = _scorer.maxScoreFrom(garble, words, mask, popsCap);
        if (currentScore + remaining < maxScore) return;
      }

      // Try popping each active letter
      for (var i = 0; i < n; i++) {
        final bit = 1 << i;
        if ((mask & bit) == 0) continue;

        final newMask = mask & ~bit;
        final subseq = _subseq(garble, newMask);
        final newPops = popsSinceLastBank + 1;

        if (newMask > 0 && words.contains(subseq)) {
          // Word formed - bank it (automatic in the game, no choice to skip)
          final score = Scorer.wordScore(subseq.length, newPops);
          final step = RouteStep(
            word: subseq,
            popsSinceLastBank: newPops,
            score: score,
            mask: newMask,
          );
          currentPath.add(step);
          explore(newMask, 0, currentPath, currentScore + score);
          currentPath.removeLast();
        } else {
          // Not a valid word (or last letter) - continue popping
          explore(newMask, newPops, currentPath, currentScore);
        }
      }
    }

    explore(fullMask, 0, [], 0);

    // Sort routes by score descending, then by word count ascending
    routes.sort((a, b) {
      final scoreCmp = b.totalScore.compareTo(a.totalScore);
      if (scoreCmp != 0) return scoreCmp;
      return a.wordCount.compareTo(b.wordCount);
    });

    return RouteAnalysis(
      garble: garble,
      validWords: words,
      routes: routes,
      maxScore: maxScore,
      limitReached: limitReached,
    );
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
