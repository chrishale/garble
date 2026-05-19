import 'dart:math';

import 'package:flutter/material.dart';

import '../models/level.dart';
import '../services/analytics_service.dart';
import '../services/candidate_service.dart';
import '../services/dictionary_service.dart';
import '../services/progress.dart';
import '../services/scorer.dart';
import 'test_game_screen.dart';

/// Coordinator screen for test mode sessions.
///
/// Manages the flow of random levels from Firestore and tracks session progress.
/// Persists which garbles have been tested so users only see new levels.
class TestModeScreen extends StatefulWidget {
  final Scorer scorer;
  final Progress progress;
  final DictionaryService dictionaryService;

  const TestModeScreen({
    super.key,
    required this.scorer,
    required this.progress,
    required this.dictionaryService,
  });

  @override
  State<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends State<TestModeScreen> {
  final _random = Random();
  final _sessionPlayedGarbles = <String>{}; // Garbles played this session
  int _levelsTestedThisSession = 0;

  List<Level>? _allLevels;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    try {
      // Always fetch fresh levels from Firestore
      final levels = await CandidateService.instance.refresh();

      // Initialize words and max scores for each level
      for (final level in levels) {
        if (level.usesDictionary) {
          final words = widget.dictionaryService.findWordsForGarble(level.garble);
          level.initializeWords(words);
        }
        level.maxScore ??= widget.scorer.maxScore(level.garble, level.words);
      }

      _allLevels = levels;

      // Start analytics session
      await AnalyticsService.instance.startTestSession();

      if (mounted) {
        setState(() => _isLoading = false);
        _startNextLevel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startNextLevel() async {
    final levels = _allLevels;
    if (levels == null || levels.isEmpty) {
      _showNoLevelsAvailable();
      return;
    }

    // Pick a random level not yet tested (ever) and not played this session
    final alreadyTested = widget.progress.testedGarbles;
    final available = levels
        .where((l) => !alreadyTested.contains(l.garble))
        .where((l) => !_sessionPlayedGarbles.contains(l.garble))
        .toList();

    if (available.isEmpty) {
      // All levels tested - show completion
      _showAllLevelsTested();
      return;
    }

    final level = available[_random.nextInt(available.length)];
    _sessionPlayedGarbles.add(level.garble);

    if (!mounted) return;

    // Push TestGameScreen and wait for result
    final result = await Navigator.of(context).push<TestGameResult>(
      MaterialPageRoute(
        builder: (_) => TestGameScreen(
          level: level,
          scorer: widget.scorer,
          levelsCompleted: _levelsTestedThisSession,
          totalRemaining: available.length,
        ),
      ),
    );

    // Handle result when TestGameScreen pops
    if (!mounted) return;

    if (result != null) {
      await widget.progress.recordTestedGarble(level.garble);
      _levelsTestedThisSession++;
      _startNextLevel();
    } else {
      // User exited test mode - pop back to level select
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showNoLevelsAvailable() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('No Levels Available'),
        content: const Text(
          'There are no test levels in the database yet. '
          'Please add some levels using the CLI tool.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAllLevelsTested() {
    final totalTested = widget.progress.testedGarbles.length;
    final totalLevels = _allLevels?.length ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('All Levels Tested'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _levelsTestedThisSession > 0
                  ? 'You tested $_levelsTestedThisSession new levels this session ($totalTested/$totalLevels total).'
                  : 'You\'ve already tested all $totalTested levels.',
            ),
            const SizedBox(height: 12),
            const Text('Thank you for your feedback!'),
            const SizedBox(height: 16),
            Text(
              'Want to retest levels? Tap "Reset" to start fresh.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.progress.clearTestedGarbles();
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              // Restart session with cleared progress
              _sessionPlayedGarbles.clear();
              _levelsTestedThisSession = 0;
              _startNextLevel();
            },
            child: const Text('RESET'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Test Mode'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load levels',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                    });
                    _initSession();
                  },
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading state
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              _isLoading ? 'Loading levels...' : 'Starting test session...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
