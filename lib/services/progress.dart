import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Progress extends ChangeNotifier {
  static const _key = 'maxLevelCleared';

  final SharedPreferences _prefs;
  int _maxLevelCleared;

  Progress._(this._prefs, this._maxLevelCleared);

  static Future<Progress> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Progress._(prefs, prefs.getInt(_key) ?? 0);
  }

  /// Highest level number that has been perfected (score == max).
  int get maxLevelCleared => _maxLevelCleared;

  bool isUnlocked(int levelNumber) => levelNumber <= _maxLevelCleared + 1;

  Future<void> recordPerfect(int levelNumber) async {
    if (levelNumber <= _maxLevelCleared) return;
    _maxLevelCleared = levelNumber;
    await _prefs.setInt(_key, _maxLevelCleared);
    notifyListeners();
  }

  @visibleForTesting
  Future<void> reset() async {
    _maxLevelCleared = 0;
    await _prefs.remove(_key);
    notifyListeners();
  }
}
