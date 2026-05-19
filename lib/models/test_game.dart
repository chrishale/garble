import '../services/analytics_service.dart';
import 'game.dart';

/// GameController subclass that tracks every pop for analytics.
class TestGameController extends GameController {
  int _totalPops = 0;

  TestGameController({required super.level, required super.scorer});

  int get totalPops => _totalPops;

  @override
  void pop(int position) {
    if (gameOver) return;
    if (!isPositionActive(position)) return;

    // Capture state before pop
    final previousBankedCount = banked.length;
    final previousPopsSinceLastBank = popsSinceLastBank;

    // Execute the pop
    super.pop(position);
    _totalPops++;

    // Capture state after pop
    final newBanked = banked.length > previousBankedCount;
    final lastBankedWord = newBanked ? banked.last : null;

    // Record to analytics
    AnalyticsService.instance.recordPop(
      position: position,
      newMask: mask,
      resultingLetters: currentLetters,
      formedWord: newBanked,
      bankedWord: lastBankedWord?.word,
      wordScore: lastBankedWord?.score,
      popsSinceLastBank: newBanked ? previousPopsSinceLastBank + 1 : popsSinceLastBank,
    );
  }

  @override
  void reset() {
    super.reset();
    _totalPops = 0;
    // Re-log level start on reset
    AnalyticsService.instance.logLevelStart(
      levelNumber: level.number,
      garble: level.garble,
      maxScore: level.maxScore ?? 0,
      wordCount: level.words.length,
    );
  }
}
