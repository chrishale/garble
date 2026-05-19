import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Event data for a single pop action.
class PopEvent {
  final DateTime timestamp;
  final int position;
  final int newMask;
  final String resultingLetters;
  final bool formedWord;
  final String? bankedWord;
  final int? wordScore;
  final int popsSinceLastBank;

  PopEvent({
    required this.timestamp,
    required this.position,
    required this.newMask,
    required this.resultingLetters,
    required this.formedWord,
    this.bankedWord,
    this.wordScore,
    required this.popsSinceLastBank,
  });
}

/// Singleton analytics service for test mode tracking.
///
/// Tracks detailed player routes through levels including every pop,
/// banked words, skips, and emoji feedback. Sends events to both
/// Firebase Analytics and PostHog.
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  final FirebaseAnalytics _firebase = FirebaseAnalytics.instance;
  final Posthog _posthog = Posthog();

  // Test session tracking
  String _currentSessionId = '';
  int _currentLevelNumber = 0;
  String _currentGarble = '';
  DateTime? _levelStartTime;
  final List<PopEvent> _popBuffer = [];

  /// Start a new test session.
  Future<void> startTestSession() async {
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    final params = {'session_id': _currentSessionId};

    // Firebase
    await _firebase.logEvent(
      name: 'test_session_start',
      parameters: params,
    );

    // PostHog
    await _posthog.capture(
      eventName: 'test_session_start',
      properties: params,
    );
  }

  /// Log level start.
  Future<void> logLevelStart({
    required int levelNumber,
    required String garble,
    required int maxScore,
    required int wordCount,
  }) async {
    _currentLevelNumber = levelNumber;
    _currentGarble = garble;
    _levelStartTime = DateTime.now();
    _popBuffer.clear();

    final params = {
      'session_id': _currentSessionId,
      'level_number': levelNumber,
      'garble': garble,
      'max_score': maxScore,
      'word_count': wordCount,
      'garble_length': garble.length,
    };

    // Firebase
    await _firebase.logEvent(
      name: 'test_level_start',
      parameters: params,
    );

    // PostHog
    await _posthog.capture(
      eventName: 'test_level_start',
      properties: params,
    );
  }

  /// Record each pop action - buffered for batch sending on level end.
  void recordPop({
    required int position,
    required int newMask,
    required String resultingLetters,
    required bool formedWord,
    required String? bankedWord,
    required int? wordScore,
    required int popsSinceLastBank,
  }) {
    _popBuffer.add(PopEvent(
      timestamp: DateTime.now(),
      position: position,
      newMask: newMask,
      resultingLetters: resultingLetters,
      formedWord: formedWord,
      bankedWord: bankedWord,
      wordScore: wordScore,
      popsSinceLastBank: popsSinceLastBank,
    ));
  }

  /// Log level completion with full route.
  Future<void> logLevelComplete({
    required int finalScore,
    required int maxScore,
    required List<String> bankedWords,
    required bool reachedMax,
  }) async {
    final duration = _levelStartTime != null
        ? DateTime.now().difference(_levelStartTime!).inMilliseconds
        : 0;

    // Encode route as compact string: "pos1,pos2,pos3|word1,word2"
    final route = _encodeRoute();
    final scorePercentage = maxScore > 0 ? (finalScore * 100 ~/ maxScore) : 0;

    final params = {
      'session_id': _currentSessionId,
      'level_number': _currentLevelNumber,
      'garble': _currentGarble,
      'final_score': finalScore,
      'max_score': maxScore,
      'score_percentage': scorePercentage,
      'reached_max': reachedMax,
      'duration_ms': duration,
      'pop_count': _popBuffer.length,
      'word_count': bankedWords.length,
      'banked_words': bankedWords.join(','),
      'route': route,
    };

    // Firebase (limited params - no lists, booleans as int)
    await _firebase.logEvent(
      name: 'test_level_complete',
      parameters: {
        'session_id': _currentSessionId,
        'level_number': _currentLevelNumber,
        'final_score': finalScore,
        'max_score': maxScore,
        'score_percentage': scorePercentage,
        'reached_max': reachedMax ? 1 : 0,
        'duration_ms': duration,
        'pop_count': _popBuffer.length,
        'word_count': bankedWords.length,
        'route': route,
      },
    );

    // PostHog (full params)
    await _posthog.capture(
      eventName: 'test_level_complete',
      properties: params,
    );

    // Log individual pops for detailed analysis
    await _flushPopEvents();
  }

  /// Log level skip.
  Future<void> logLevelSkip({
    required int currentScore,
    required int maxScore,
    required int popsUsed,
  }) async {
    final duration = _levelStartTime != null
        ? DateTime.now().difference(_levelStartTime!).inMilliseconds
        : 0;

    final wordsFound = _popBuffer.where((p) => p.formedWord).length;

    final params = {
      'session_id': _currentSessionId,
      'level_number': _currentLevelNumber,
      'garble': _currentGarble,
      'current_score': currentScore,
      'max_score': maxScore,
      'pops_used': popsUsed,
      'duration_ms': duration,
      'word_count': wordsFound,
    };

    // Firebase
    await _firebase.logEvent(
      name: 'test_level_skip',
      parameters: params,
    );

    // PostHog
    await _posthog.capture(
      eventName: 'test_level_skip',
      properties: params,
    );

    // Also log pops for skipped levels
    await _flushPopEvents();
  }

  /// Log level abandoned (user exited test mode mid-puzzle).
  Future<void> logLevelAbandoned({
    required int currentScore,
    required int maxScore,
    required int popsUsed,
  }) async {
    final duration = _levelStartTime != null
        ? DateTime.now().difference(_levelStartTime!).inMilliseconds
        : 0;

    final wordsFound = _popBuffer.where((p) => p.formedWord).length;
    final scorePercentage = maxScore > 0 ? (currentScore * 100 ~/ maxScore) : 0;

    final params = {
      'session_id': _currentSessionId,
      'level_number': _currentLevelNumber,
      'garble': _currentGarble,
      'current_score': currentScore,
      'max_score': maxScore,
      'score_percentage': scorePercentage,
      'pops_used': popsUsed,
      'duration_ms': duration,
      'word_count': wordsFound,
    };

    // Firebase
    await _firebase.logEvent(
      name: 'test_level_abandoned',
      parameters: params,
    );

    // PostHog
    await _posthog.capture(
      eventName: 'test_level_abandoned',
      properties: params,
    );

    // Also log pops for abandoned levels
    await _flushPopEvents();
  }

  /// Log emoji feedback.
  Future<void> logFeedback({
    required String emoji,
    required bool wasSkipped,
    required int? finalScore,
    required int maxScore,
  }) async {
    // Firebase params (booleans as int)
    final firebaseParams = <String, Object>{
      'session_id': _currentSessionId,
      'level_number': _currentLevelNumber,
      'garble': _currentGarble,
      'emoji': emoji,
      'was_skipped': wasSkipped ? 1 : 0,
      'max_score': maxScore,
    };

    if (finalScore != null) {
      firebaseParams['final_score'] = finalScore;
      if (maxScore > 0) {
        firebaseParams['score_percentage'] = finalScore * 100 ~/ maxScore;
      }
    }

    // Firebase
    await _firebase.logEvent(
      name: 'test_level_feedback',
      parameters: firebaseParams,
    );

    // PostHog (supports booleans natively)
    final posthogParams = <String, Object>{
      'session_id': _currentSessionId,
      'level_number': _currentLevelNumber,
      'garble': _currentGarble,
      'emoji': emoji,
      'was_skipped': wasSkipped,
      'max_score': maxScore,
    };
    if (finalScore != null) {
      posthogParams['final_score'] = finalScore;
      if (maxScore > 0) {
        posthogParams['score_percentage'] = finalScore * 100 ~/ maxScore;
      }
    }
    await _posthog.capture(
      eventName: 'test_level_feedback',
      properties: posthogParams,
    );
  }

  String _encodeRoute() {
    final positions = _popBuffer.map((p) => p.position.toString()).join(',');
    final words = _popBuffer
        .where((p) => p.bankedWord != null)
        .map((p) => p.bankedWord!)
        .join(',');
    return '$positions|$words';
  }

  Future<void> _flushPopEvents() async {
    for (var i = 0; i < _popBuffer.length; i++) {
      final pop = _popBuffer[i];

      // Firebase params (booleans as int)
      final firebaseParams = <String, Object>{
        'session_id': _currentSessionId,
        'level_number': _currentLevelNumber,
        'pop_index': i,
        'position': pop.position,
        'new_mask': pop.newMask,
        'resulting_letters': pop.resultingLetters,
        'formed_word': pop.formedWord ? 1 : 0,
        'pops_since_bank': pop.popsSinceLastBank,
        'timestamp_ms': pop.timestamp.millisecondsSinceEpoch,
      };

      // PostHog params (native booleans)
      final posthogParams = <String, Object>{
        'session_id': _currentSessionId,
        'level_number': _currentLevelNumber,
        'pop_index': i,
        'position': pop.position,
        'new_mask': pop.newMask,
        'resulting_letters': pop.resultingLetters,
        'formed_word': pop.formedWord,
        'pops_since_bank': pop.popsSinceLastBank,
        'timestamp_ms': pop.timestamp.millisecondsSinceEpoch,
      };

      if (pop.bankedWord != null) {
        firebaseParams['banked_word'] = pop.bankedWord!;
        posthogParams['banked_word'] = pop.bankedWord!;
      }
      if (pop.wordScore != null) {
        firebaseParams['word_score'] = pop.wordScore!;
        posthogParams['word_score'] = pop.wordScore!;
      }

      // Firebase
      await _firebase.logEvent(
        name: 'test_pop',
        parameters: firebaseParams,
      );

      // PostHog
      await _posthog.capture(
        eventName: 'test_pop',
        properties: posthogParams,
      );
    }
    _popBuffer.clear();
  }
}
