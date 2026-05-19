import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/levels.dart';
import '../models/level.dart';
import '../services/dictionary_service.dart';
import '../services/progress.dart';
import '../services/scorer.dart';
import '../widgets/garble_stage.dart';
import 'game_screen.dart';
import 'test_mode_screen.dart';

class LevelSelectScreen extends StatelessWidget {
  final Scorer scorer;
  final Progress progress;
  final DictionaryService dictionaryService;

  const LevelSelectScreen({
    super.key,
    required this.scorer,
    required this.progress,
    required this.dictionaryService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SvgPicture.asset(
                  'assets/svg/garble.svg',
                  height: 120,
                  semanticsLabel: 'Garble',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pop letters. Find words. Hit max to unlock the next level.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 16),
              Expanded(
                child: ListenableBuilder(
                  listenable: progress,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: kLevels.length + 1,
                    separatorBuilder: (_, i) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => (i == 0)
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TestModeScreen(
                                      scorer: scorer,
                                      progress: progress,
                                      dictionaryService: dictionaryService,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('TEST MODE'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 24,
                                ),
                                side: BorderSide(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : _LevelCard(
                            level: kLevels[i - 1],
                            scorer: scorer,
                            progress: progress,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final Level level;
  final Scorer scorer;
  final Progress progress;

  const _LevelCard({
    required this.level,
    required this.scorer,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocked = progress.isUnlocked(level.number);
    final cleared = level.number <= progress.maxLevelCleared;
    final foundCount = progress.foundWordCount(level.number);
    final totalWords = level.words.length;

    final bgColor = theme.colorScheme.surfaceContainerHighest;
    final onDim = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: unlocked
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      level: level,
                      scorer: scorer,
                      progress: progress,
                    ),
                  ),
                );
              }
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Clear Level ${level.number - 1} with max score to unlock',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.45,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cleared
                        ? theme.colorScheme.primary
                        : unlocked
                        ? theme.colorScheme.primary.withValues(alpha: 0.4)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: unlocked
                      ? Text(
                          '${level.number}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Icon(Icons.lock_outline, color: onDim, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        level.garble,
                        style: TextStyle(
                          fontFamily: kGarbleFontFamily,
                          fontSize: 32,
                          letterSpacing: 3,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Max ${level.maxScore ?? "—"} pts',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onDim,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$foundCount / $totalWords words',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (cleared)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary)
                else if (unlocked)
                  Icon(Icons.chevron_right, color: onDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
