import 'dart:convert';
import 'dart:io';

import 'package:garble/core/dictionary.dart';
import 'package:garble/core/word_finder.dart';
import 'package:garble/services/route_analyzer.dart';
import 'package:garble/services/scorer.dart';

// Analyze all possible routes through a Garble puzzle.
//
// Usage: dart run garble:analyze_routes <garble> [options]
//
// Options:
//   --dict=us|uk    Dictionary to use (default: us)
//   --all           Show all routes, not just max-score routes
//   --limit=N       Max routes to show when using --all (default: 100)
//   --json          Output in JSON format
void main(List<String> args) async {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    _printUsage();
    exit(args.isEmpty ? 1 : 0);
  }

  final garble = args[0].toUpperCase();

  // Parse flags
  var dictPath = 'assets/dictionaries/twl06.txt';
  var dictName = 'US (TWL06)';
  var showAll = false;
  var limit = 100;
  var jsonOutput = false;

  for (final arg in args.skip(1)) {
    if (arg.startsWith('--dict=')) {
      final value = arg.substring(7).toLowerCase();
      if (value == 'uk') {
        dictPath = 'assets/dictionaries/sowpods.txt';
        dictName = 'UK (SOWPODS)';
      }
    } else if (arg == '--all') {
      showAll = true;
    } else if (arg.startsWith('--limit=')) {
      limit = int.tryParse(arg.substring(8)) ?? 100;
    } else if (arg == '--json') {
      jsonOutput = true;
    }
  }

  // Load dictionary
  final file = File(dictPath);
  if (!file.existsSync()) {
    stderr.writeln('Dictionary not found: $dictPath');
    stderr.writeln('Make sure you run this from the project root directory.');
    exit(1);
  }

  final content = await file.readAsString();
  final dictionary = Dictionary.fromText(content);
  final finder = WordFinder(dictionary);

  // Find valid words
  final words = finder.findWords(garble);
  if (words.isEmpty) {
    if (jsonOutput) {
      stdout.writeln(jsonEncode({
        'garble': garble,
        'error': 'No valid words found',
      }));
    } else {
      stderr.writeln('No valid words found in garble: $garble');
    }
    exit(1);
  }

  // Analyze routes
  final analyzer = RouteAnalyzer();
  final analysis = analyzer.analyze(
    garble,
    words,
    maxScoreOnly: !showAll,
    limit: showAll ? limit : null,
  );

  if (jsonOutput) {
    _outputJson(analysis, dictName);
  } else {
    _outputText(analysis, dictName, showAll, limit);
  }
}

void _printUsage() {
  stdout.writeln('Analyze all possible routes through a Garble puzzle.');
  stdout.writeln();
  stdout.writeln('Usage: dart run garble:analyze_routes <garble> [options]');
  stdout.writeln();
  stdout.writeln('Options:');
  stdout.writeln('  --dict=us|uk    Dictionary to use (default: us)');
  stdout.writeln('  --all           Show all routes, not just max-score routes');
  stdout.writeln('  --limit=N       Max routes when using --all (default: 100)');
  stdout.writeln('  --json          Output in JSON format');
  stdout.writeln('  --help, -h      Show this help');
  stdout.writeln();
  stdout.writeln('Examples:');
  stdout.writeln('  dart run garble:analyze_routes BCATS');
  stdout.writeln('  dart run garble:analyze_routes BCATS --all --limit=50');
  stdout.writeln('  dart run garble:analyze_routes TRAINS --dict=uk --json');
}

void _outputJson(RouteAnalysis analysis, String dictName) {
  final json = {
    'garble': analysis.garble,
    'dictionary': dictName,
    'validWordCount': analysis.validWords.length,
    'validWords': analysis.validWords.toList()..sort(),
    'maxScore': analysis.maxScore,
    'routeCount': analysis.routes.length,
    'limitReached': analysis.limitReached,
    'routes': analysis.routes.map((route) {
      return {
        'score': route.totalScore,
        'isMaxScore': route.totalScore == analysis.maxScore,
        'wordCount': route.wordCount,
        'averagePops': double.parse(route.averagePops.toStringAsFixed(2)),
        'bonusCount': route.bonusCount,
        'steps': route.steps.map((step) {
          return {
            'word': step.word,
            'pops': step.popsSinceLastBank,
            'score': step.score,
            'baseScore': step.baseScore,
            'bonusScore': step.bonusScore,
            'hasBonus': step.hasBonus,
          };
        }).toList(),
      };
    }).toList(),
  };

  final encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(json));
}

void _outputText(
  RouteAnalysis analysis,
  String dictName,
  bool showAll,
  int limit,
) {
  final garble = analysis.garble;
  final maxScore = analysis.maxScore;
  final routes = analysis.routes;

  stdout.writeln('═' * 60);
  stdout.writeln('GARBLE ROUTE ANALYSIS: $garble');
  stdout.writeln('═' * 60);
  stdout.writeln('Dictionary: $dictName');
  stdout.writeln('Valid words: ${analysis.validWords.length}');
  stdout.writeln();

  stdout.writeln('Max score: $maxScore points');

  if (showAll) {
    final maxRoutes = analysis.maxScoreRoutes;
    stdout.writeln('Routes at max score: ${maxRoutes.length}');
    stdout.writeln('Total routes found: ${routes.length}${analysis.limitReached ? " (limit reached)" : ""}');
  } else {
    stdout.writeln('Found ${routes.length} route${routes.length == 1 ? "" : "s"} achieving max score');
  }
  stdout.writeln();

  // Show max-score routes in detail
  final maxScoreRoutes = analysis.maxScoreRoutes;
  if (maxScoreRoutes.isNotEmpty) {
    stdout.writeln('─' * 60);
    stdout.writeln('MAX SCORE ROUTES (${maxScore} points)');
    stdout.writeln('─' * 60);

    for (var i = 0; i < maxScoreRoutes.length; i++) {
      final route = maxScoreRoutes[i];
      stdout.writeln();
      stdout.writeln('ROUTE ${i + 1} of ${maxScoreRoutes.length}');
      _printRouteTable(route);
      stdout.writeln(
        'Total: ${route.totalScore} | '
        'Avg pops/word: ${route.averagePops.toStringAsFixed(2)} | '
        'Bonuses: ${route.bonusCount}',
      );
    }
  }

  // Show all routes if requested
  if (showAll && routes.length > maxScoreRoutes.length) {
    stdout.writeln();
    stdout.writeln('─' * 60);
    stdout.writeln('ALL ROUTES (${routes.length} found${analysis.limitReached ? ", limit $limit" : ""})');
    stdout.writeln('─' * 60);
    stdout.writeln();
    stdout.writeln(' #   Score  Words                                    Avg Pops');
    stdout.writeln('───  ─────  ───────────────────────────────────────  ────────');

    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      final isMax = route.totalScore == maxScore;
      final num = '${i + 1}'.padLeft(3);
      final score = '${route.totalScore}${isMax ? "*" : " "}';
      final words = route.steps
          .map((s) => '${s.word}(${s.popsSinceLastBank})')
          .join('→');
      final avgPops = route.averagePops.toStringAsFixed(2);
      stdout.writeln('$num  ${score.padRight(5)}  ${words.padRight(40)}  $avgPops');
    }

    // Score distribution
    stdout.writeln();
    stdout.writeln('─' * 60);
    stdout.writeln('SCORE DISTRIBUTION');
    stdout.writeln('─' * 60);
    final dist = analysis.scoreDistribution;
    final sortedScores = dist.keys.toList()..sort((a, b) => b.compareTo(a));
    final maxCount = dist.values.reduce((a, b) => a > b ? a : b);

    for (final score in sortedScores) {
      final count = dist[score]!;
      final barLen = (count / maxCount * 20).round();
      final bar = '█' * barLen;
      final isMax = score == maxScore;
      stdout.writeln(
        '  ${score.toString().padLeft(3)} pts: $bar ${count} route${count == 1 ? "" : "s"}${isMax ? " *" : ""}',
      );
    }
  }

  // Overall metrics
  stdout.writeln();
  stdout.writeln('─' * 60);
  stdout.writeln('OVERALL METRICS');
  stdout.writeln('─' * 60);
  if (maxScoreRoutes.isNotEmpty) {
    final avgPops = maxScoreRoutes
            .map((r) => r.averagePops)
            .reduce((a, b) => a + b) /
        maxScoreRoutes.length;
    final avgWords = maxScoreRoutes
            .map((r) => r.wordCount)
            .reduce((a, b) => a + b) /
        maxScoreRoutes.length;
    stdout.writeln('  Routes at max score: ${maxScoreRoutes.length}');
    stdout.writeln('  Avg words per route: ${avgWords.toStringAsFixed(1)}');
    stdout.writeln('  Avg pops per word: ${avgPops.toStringAsFixed(2)}');
  }
}

void _printRouteTable(Route route) {
  // Calculate column widths
  const numWidth = 3;
  var wordWidth = 4; // "Word"
  const popsWidth = 4;
  const scoreWidth = 5;
  const noteWidth = 11;

  for (final step in route.steps) {
    if (step.word.length > wordWidth) wordWidth = step.word.length;
  }

  final rowWidth = numWidth + wordWidth + popsWidth + scoreWidth + noteWidth + 14;

  // Header
  stdout.writeln('┌${"─" * (numWidth + 2)}┬${"─" * (wordWidth + 2)}┬${"─" * (popsWidth + 2)}┬${"─" * (scoreWidth + 2)}┬${"─" * (noteWidth + 2)}┐');
  stdout.writeln(
    '│ ${"#".padRight(numWidth)} │ ${"Word".padRight(wordWidth)} │ ${"Pops".padRight(popsWidth)} │ ${"Score".padRight(scoreWidth)} │ ${"Note".padRight(noteWidth)} │',
  );
  stdout.writeln('├${"─" * (numWidth + 2)}┼${"─" * (wordWidth + 2)}┼${"─" * (popsWidth + 2)}┼${"─" * (scoreWidth + 2)}┼${"─" * (noteWidth + 2)}┤');

  // Rows
  for (var i = 0; i < route.steps.length; i++) {
    final step = route.steps[i];
    final num = '${i + 1}'.padRight(numWidth);
    final word = step.word.padRight(wordWidth);
    final pops = '${step.popsSinceLastBank}'.padRight(popsWidth);
    final score = '${step.score}'.padRight(scoreWidth);
    final note = (step.hasBonus ? '1-POP BONUS' : '').padRight(noteWidth);
    stdout.writeln('│ $num │ $word │ $pops │ $score │ $note │');
  }

  stdout.writeln('└${"─" * (numWidth + 2)}┴${"─" * (wordWidth + 2)}┴${"─" * (popsWidth + 2)}┴${"─" * (scoreWidth + 2)}┴${"─" * (noteWidth + 2)}┘');
}
