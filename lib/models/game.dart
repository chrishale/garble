import 'package:flutter/foundation.dart';

import '../services/scorer.dart';
import 'level.dart';

class BankedWord {
  final String word;
  final int score;
  final int popsUsed;
  final bool bonus;

  const BankedWord({
    required this.word,
    required this.score,
    required this.popsUsed,
    required this.bonus,
  });
}

class GameController extends ChangeNotifier {
  final Level level;
  final Scorer scorer;

  late int _mask;
  int _popsSinceLastBank = 0;
  final List<BankedWord> _banked = [];
  int _score = 0;
  bool _gameOver = false;

  GameController({required this.level, required this.scorer}) {
    _mask = (1 << level.garble.length) - 1;
  }

  int get mask => _mask;
  int get score => _score;
  bool get gameOver => _gameOver;
  int get popsSinceLastBank => _popsSinceLastBank;
  List<BankedWord> get banked => List.unmodifiable(_banked);

  int get remainingCount {
    var m = _mask;
    var c = 0;
    while (m != 0) {
      c += m & 1;
      m >>= 1;
    }
    return c;
  }

  bool isPositionActive(int position) => (_mask & (1 << position)) != 0;

  String get currentLetters {
    final sb = StringBuffer();
    for (var i = 0; i < level.garble.length; i++) {
      if ((_mask & (1 << i)) != 0) sb.write(level.garble[i]);
    }
    return sb.toString();
  }

  bool get currentIsWord => level.words.contains(currentLetters);

  void pop(int position) {
    if (_gameOver) return;
    if (!isPositionActive(position)) return;

    _mask &= ~(1 << position);
    _popsSinceLastBank++;

    if (_mask != 0) {
      final subseq = currentLetters;
      if (level.words.contains(subseq)) {
        final gained = Scorer.wordScore(subseq.length, _popsSinceLastBank);
        final bonus = _popsSinceLastBank == 1;
        _banked.add(BankedWord(
          word: subseq,
          score: gained,
          popsUsed: _popsSinceLastBank,
          bonus: bonus,
        ));
        _score += gained;
        _popsSinceLastBank = 0;
      }
    }

    if (_mask == 0 ||
        !scorer.hasReachableWord(level.garble, _mask, level.words)) {
      _gameOver = true;
    }

    notifyListeners();
  }

  void reset() {
    _mask = (1 << level.garble.length) - 1;
    _popsSinceLastBank = 0;
    _banked.clear();
    _score = 0;
    _gameOver = false;
    notifyListeners();
  }
}
