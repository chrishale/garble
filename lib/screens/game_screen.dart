import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../models/game.dart';
import '../models/level.dart';
import '../services/progress.dart';
import '../services/scorer.dart';
import '../widgets/letter_tile.dart';

class GameScreen extends StatefulWidget {
  final Level level;
  final Scorer scorer;
  final Progress progress;

  const GameScreen({
    super.key,
    required this.level,
    required this.scorer,
    required this.progress,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GameController(level: widget.level, scorer: widget.scorer);
    _controller.addListener(_handleChange);
    _logBestPath();
  }

  void _logBestPath() {
    final level = widget.level;
    final path = widget.scorer.bestPath(level.garble, level.words);
    final max = level.maxScore ?? 0;
    final chain = [level.garble, ...path].join(' → ');
    debugPrint('Level ${level.number} [${level.garble}] max=$max  path: $chain');
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleChange() {
    if (mounted) setState(() {});
    if (_controller.gameOver) {
      final maxScore = widget.level.maxScore ?? 0;
      if (_controller.score >= maxScore && maxScore > 0) {
        widget.progress.recordPerfect(widget.level.number);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGameOver());
    }
  }

  Level? _nextLevel() {
    final idx = kLevels.indexWhere((l) => l.number == widget.level.number);
    if (idx < 0 || idx + 1 >= kLevels.length) return null;
    return kLevels[idx + 1];
  }

  void _maybeShowGameOver() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final maxScore = widget.level.maxScore ?? 0;
    final isPerfect = _controller.score >= maxScore && maxScore > 0;
    final next = _nextLevel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => _GameOverSheet(
        score: _controller.score,
        maxScore: maxScore,
        isPerfect: isPerfect,
        nextLevel: next,
        onRetry: () {
          Navigator.of(sheetCtx).pop();
          _controller.reset();
        },
        onBack: () {
          Navigator.of(sheetCtx).pop();
          Navigator.of(context).pop();
        },
        onNext: (isPerfect && next != null)
            ? () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      level: next,
                      scorer: widget.scorer,
                      progress: widget.progress,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = widget.level;
    final maxScore = level.maxScore ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Level ${level.number}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart',
            onPressed: _controller.reset,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScoreBar(score: _controller.score, max: maxScore),
              const SizedBox(height: 24),
              _StatusLine(controller: _controller),
              const SizedBox(height: 16),
              _LettersRow(controller: _controller),
              const SizedBox(height: 24),
              Text(
                'BANKED WORDS',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _BankedList(controller: _controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;
  final int max;

  const _ScoreBar({required this.score, required this.max});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = max == 0 ? 0.0 : (score / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'SCORE',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            RichText(
              text: TextSpan(
                style: theme.textTheme.titleLarge,
                children: [
                  TextSpan(
                    text: '$score',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: ' / $max',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final GameController controller;

  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = controller.currentLetters;
    final isWord = controller.currentIsWord;
    final banked = controller.banked;

    String text;
    Color color;
    if (controller.gameOver) {
      text = 'No more words — game over';
      color = theme.colorScheme.error;
    } else if (banked.isEmpty && controller.popsSinceLastBank == 0) {
      text = 'Tap a letter to pop it';
      color = theme.colorScheme.onSurfaceVariant;
    } else if (isWord && banked.isNotEmpty && banked.last.word == current) {
      text = 'BANKED "$current" +${banked.last.score}';
      color = theme.colorScheme.primary;
    } else {
      final pops = controller.popsSinceLastBank;
      text = 'Popped $pops — keep going';
      color = theme.colorScheme.onSurfaceVariant;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Text(
        text,
        key: ValueKey(text),
        style: theme.textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LettersRow extends StatelessWidget {
  final GameController controller;

  const _LettersRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final level = controller.level;

    // The row always fits a single line sized for the initial garble so that
    // tiles don't grow as letters are popped.
    final totalTiles = level.garble.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxTileSize = 56.0;
        const minTileSize = 24.0;
        const spacing = 8.0;
        final available = constraints.maxWidth;
        final rawTileSize =
            (available - spacing * (totalTiles - 1)) / totalTiles;
        final tileSize = rawTileSize.clamp(minTileSize, maxTileSize);
        final actualSpacing = totalTiles > 1
            ? ((available - tileSize * totalTiles) / (totalTiles - 1)).clamp(
                4.0,
                spacing,
              )
            : 0.0;

        final tiles = <Widget>[];
        for (var i = 0; i < totalTiles; i++) {
          final active = controller.isPositionActive(i);
          if (i > 0) tiles.add(SizedBox(width: actualSpacing));
          tiles.add(
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: active ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !active,
                child: LetterTile(
                  key: ValueKey('pos-$i'),
                  letter: level.garble[i],
                  size: tileSize,
                  onTap: controller.gameOver ? null : () => controller.pop(i),
                  highlighted: active && controller.currentIsWord,
                ),
              ),
            ),
          );
        }

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: tiles,
          ),
        );
      },
    );
  }
}

class _BankedList extends StatelessWidget {
  final GameController controller;

  const _BankedList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = controller.banked;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'None yet',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, i) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final w = items[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                w.word,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              if (w.bonus)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '1-POP BONUS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                '+${w.score}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GameOverSheet extends StatelessWidget {
  final int score;
  final int maxScore;
  final bool isPerfect;
  final Level? nextLevel;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  const _GameOverSheet({
    required this.score,
    required this.maxScore,
    required this.isPerfect,
    required this.nextLevel,
    required this.onRetry,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = maxScore == 0 ? 0 : (score * 100 / maxScore).round();
    final headline = isPerfect ? 'PERFECT!' : 'GAME OVER';
    final subline = isPerfect
        ? (nextLevel == null
              ? 'Final level cleared'
              : 'Level ${nextLevel!.number} unlocked')
        : 'Reach the max score to unlock the next level';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isPerfect
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                letterSpacing: 2,
                fontWeight: isPerfect ? FontWeight.w800 : FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: theme.textTheme.displaySmall,
                children: [
                  TextSpan(
                    text: '$score',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: ' / $maxScore',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$pct% of max',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (onNext != null)
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('NEXT LEVEL  →  ${nextLevel!.number}'),
              )
            else
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(isPerfect ? 'PLAY AGAIN' : 'TRY AGAIN'),
              ),
            const SizedBox(height: 8),
            if (onNext != null)
              TextButton(onPressed: onRetry, child: const Text('Play again')),
            TextButton(onPressed: onBack, child: const Text('Back to levels')),
          ],
        ),
      ),
    );
  }
}
