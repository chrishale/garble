import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/level.dart';
import '../models/test_game.dart';
import '../services/analytics_service.dart';
import '../services/scorer.dart';
import '../widgets/garble_stage.dart';

/// Result returned when TestGameScreen pops.
enum TestGameResult { completed, skipped }

/// Game screen for test mode with skip button and feedback collection.
class TestGameScreen extends StatefulWidget {
  final Level level;
  final Scorer scorer;
  final int levelsCompleted;
  final int totalRemaining;

  const TestGameScreen({
    super.key,
    required this.level,
    required this.scorer,
    required this.levelsCompleted,
    required this.totalRemaining,
  });

  @override
  State<TestGameScreen> createState() => _TestGameScreenState();
}

class _TestGameScreenState extends State<TestGameScreen> {
  late final TestGameController _controller;
  int _lastBankedSeen = 0;
  bool _feedbackShown = false;

  @override
  void initState() {
    super.initState();
    _controller = TestGameController(
      level: widget.level,
      scorer: widget.scorer,
    );
    _controller.addListener(_handleChange);
    _logLevelStart();
  }

  Future<void> _logLevelStart() async {
    await AnalyticsService.instance.logLevelStart(
      levelNumber: widget.level.number,
      garble: widget.level.garble,
      maxScore: widget.level.maxScore ?? 0,
      wordCount: widget.level.words.length,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleChange() {
    final banked = _controller.banked;
    if (banked.length < _lastBankedSeen) {
      _lastBankedSeen = 0;
    }
    if (banked.length > _lastBankedSeen) {
      _lastBankedSeen = banked.length;
    }
    if (mounted) setState(() {});
    if (_controller.gameOver && !_feedbackShown) {
      _feedbackShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGameOver());
    }
  }

  void _handleSkip() {
    if (_feedbackShown) return;
    _feedbackShown = true;
    _showSkipFeedbackDialog();
  }

  void _showSkipFeedbackDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => _SkipFeedbackSheet(
        score: _controller.score,
        maxScore: widget.level.maxScore ?? 0,
        onFeedback: (emoji) {
          AnalyticsService.instance.logLevelSkip(
            currentScore: _controller.score,
            maxScore: widget.level.maxScore ?? 0,
            popsUsed: _controller.totalPops,
          );
          AnalyticsService.instance.logFeedback(
            emoji: emoji,
            wasSkipped: true,
            finalScore: _controller.score,
            maxScore: widget.level.maxScore ?? 0,
          );
          Navigator.of(sheetCtx).pop(); // Pop sheet
          Navigator.of(context).pop(TestGameResult.skipped); // Pop screen
        },
      ),
    );
  }

  void _showGameOver() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    final maxScore = widget.level.maxScore ?? 0;
    final isPerfect = _controller.score >= maxScore && maxScore > 0;

    if (isPerfect) {
      // Level complete - log completion and show feedback
      AnalyticsService.instance.logLevelComplete(
        finalScore: _controller.score,
        maxScore: maxScore,
        bankedWords: _controller.banked.map((b) => b.word).toList(),
        reachedMax: true,
      );
      _showFeedbackDialog(wasCompleted: true);
    } else {
      // Game over but not complete - show retry/skip options
      _showGameOverSheet();
    }
  }

  void _showGameOverSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => _GameOverSheet(
        score: _controller.score,
        maxScore: widget.level.maxScore ?? 0,
        onRetry: () {
          Navigator.of(sheetCtx).pop();
          _feedbackShown = false;
          _controller.reset();
        },
        onSkipWithFeedback: (emoji) {
          // Log as skip with feedback
          AnalyticsService.instance.logLevelSkip(
            currentScore: _controller.score,
            maxScore: widget.level.maxScore ?? 0,
            popsUsed: _controller.totalPops,
          );
          AnalyticsService.instance.logFeedback(
            emoji: emoji,
            wasSkipped: true,
            finalScore: _controller.score,
            maxScore: widget.level.maxScore ?? 0,
          );
          Navigator.of(sheetCtx).pop(); // Pop sheet
          Navigator.of(context).pop(TestGameResult.skipped); // Pop screen
        },
      ),
    );
  }

  void _showFeedbackDialog({required bool wasCompleted}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => _FeedbackSheet(
        score: _controller.score,
        maxScore: widget.level.maxScore ?? 0,
        wasCompleted: wasCompleted,
        onFeedback: (emoji) {
          AnalyticsService.instance.logFeedback(
            emoji: emoji,
            wasSkipped: false,
            finalScore: _controller.score,
            maxScore: widget.level.maxScore ?? 0,
          );
          Navigator.of(sheetCtx).pop(); // Pop sheet
          Navigator.of(context).pop(TestGameResult.completed); // Pop screen
        },
      ),
    );
  }

  void _exitTestMode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Test Mode?'),
        content: Text(
          'You have tested ${widget.levelsCompleted} levels so far.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              // Log abandonment before exiting
              AnalyticsService.instance.logLevelAbandoned(
                currentScore: _controller.score,
                maxScore: widget.level.maxScore ?? 0,
                popsUsed: _controller.totalPops,
              );
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('EXIT'),
          ),
        ],
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
        title: Text('Test Level ${level.number}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitTestMode,
        ),
        actions: [
          TextButton(
            onPressed: _handleSkip,
            child: Text(
              'SKIP',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
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
              // Progress indicator
              Row(
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.levelsCompleted} tested this session \u2022 ${widget.totalRemaining} remaining',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'BANKED WORDS',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _BankedList(controller: _controller)),
              const SizedBox(height: 16),
              _StatusLine(controller: _controller),
              const SizedBox(height: 16),
              GarbleStage(controller: _controller),
              const SizedBox(height: 24),
              _ScoreBar(score: _controller.score, max: maxScore),
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
      text = 'No more words - game over';
      color = theme.colorScheme.error;
    } else if (banked.isEmpty && controller.popsSinceLastBank == 0) {
      text = 'Tap a letter to pop it';
      color = theme.colorScheme.onSurfaceVariant;
    } else if (isWord && banked.isNotEmpty && banked.last.word == current) {
      text = 'BANKED "$current" +${banked.last.score}';
      color = theme.colorScheme.primary;
    } else {
      final pops = controller.popsSinceLastBank;
      text = 'Popped $pops - keep going';
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

class _BankedList extends StatelessWidget {
  final GameController controller;

  const _BankedList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = controller.banked.reversed.toList();
    if (items.isEmpty) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'None yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      reverse: true,
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

/// Sheet shown when game over (no more words) but level not completed.
/// Offers retry or skip with feedback options.
class _GameOverSheet extends StatelessWidget {
  final int score;
  final int maxScore;
  final VoidCallback onRetry;
  final void Function(String emoji) onSkipWithFeedback;

  const _GameOverSheet({
    required this.score,
    required this.maxScore,
    required this.onRetry,
    required this.onSkipWithFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = maxScore == 0 ? 0 : (score * 100 / maxScore).round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'GAME OVER',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.error,
                letterSpacing: 2,
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
            const SizedBox(height: 8),
            Text(
              'Reach max score to complete the level',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('TRY AGAIN'),
            ),
            const SizedBox(height: 16),
            Text(
              'Or skip and leave feedback:',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _EmojiButton(
                  emoji: '\u{1F60A}',
                  label: 'Fun',
                  onTap: () => onSkipWithFeedback('happy'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44D}',
                  label: 'Good',
                  onTap: () => onSkipWithFeedback('thumbs_up'),
                ),
                _EmojiButton(
                  emoji: '\u{1F610}',
                  label: 'Okay',
                  onTap: () => onSkipWithFeedback('neutral'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44E}',
                  label: 'Bad',
                  onTap: () => onSkipWithFeedback('thumbs_down'),
                ),
                _EmojiButton(
                  emoji: '\u{1F621}',
                  label: 'Frustrating',
                  onTap: () => onSkipWithFeedback('angry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet shown when user taps SKIP button.
class _SkipFeedbackSheet extends StatelessWidget {
  final int score;
  final int maxScore;
  final void Function(String emoji) onFeedback;

  const _SkipFeedbackSheet({
    required this.score,
    required this.maxScore,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SKIPPING LEVEL',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'How was this level?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _EmojiButton(
                  emoji: '\u{1F60A}',
                  label: 'Fun',
                  onTap: () => onFeedback('happy'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44D}',
                  label: 'Good',
                  onTap: () => onFeedback('thumbs_up'),
                ),
                _EmojiButton(
                  emoji: '\u{1F610}',
                  label: 'Okay',
                  onTap: () => onFeedback('neutral'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44E}',
                  label: 'Bad',
                  onTap: () => onFeedback('thumbs_down'),
                ),
                _EmojiButton(
                  emoji: '\u{1F621}',
                  label: 'Frustrating',
                  onTap: () => onFeedback('angry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet shown when level is completed (max score reached).
class _FeedbackSheet extends StatelessWidget {
  final int score;
  final int maxScore;
  final bool wasCompleted;
  final void Function(String emoji) onFeedback;

  const _FeedbackSheet({
    required this.score,
    required this.maxScore,
    required this.wasCompleted,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PERFECT!',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
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
              'Level complete!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How was this level?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _EmojiButton(
                  emoji: '\u{1F60A}',
                  label: 'Fun',
                  onTap: () => onFeedback('happy'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44D}',
                  label: 'Good',
                  onTap: () => onFeedback('thumbs_up'),
                ),
                _EmojiButton(
                  emoji: '\u{1F610}',
                  label: 'Okay',
                  onTap: () => onFeedback('neutral'),
                ),
                _EmojiButton(
                  emoji: '\u{1F44E}',
                  label: 'Bad',
                  onTap: () => onFeedback('thumbs_down'),
                ),
                _EmojiButton(
                  emoji: '\u{1F621}',
                  label: 'Frustrating',
                  onTap: () => onFeedback('angry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
