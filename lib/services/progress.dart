import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Progress extends ChangeNotifier {
  static const _key = 'maxLevelCleared';
  static const _foundPrefix = 'foundWords_L';

  final SharedPreferences _prefs;
  int _maxLevelCleared;
  final Map<int, Set<String>> _foundWords;

  Progress._(this._prefs, this._maxLevelCleared, this._foundWords);

  static Future<Progress> load() async {
    final prefs = await SharedPreferences.getInstance();
    final found = <int, Set<String>>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_foundPrefix)) continue;
      final levelNumber = int.tryParse(key.substring(_foundPrefix.length));
      if (levelNumber == null) continue;
      final words = prefs.getStringList(key);
      if (words == null) continue;
      found[levelNumber] = words.toSet();
    }
    return Progress._(prefs, prefs.getInt(_key) ?? 0, found);
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

  Set<String> foundWords(int levelNumber) {
    final set = _foundWords[levelNumber];
    if (set == null) return const <String>{};
    return Set.unmodifiable(set);
  }

  int foundWordCount(int levelNumber) => _foundWords[levelNumber]?.length ?? 0;

  Future<void> recordFoundWord(int levelNumber, String word) async {
    final set = _foundWords.putIfAbsent(levelNumber, () => <String>{});
    if (!set.add(word)) return;
    await _prefs.setStringList('$_foundPrefix$levelNumber', set.toList());
    notifyListeners();
  }

  @visibleForTesting
  Future<void> reset() async {
    _maxLevelCleared = 0;
    await _prefs.remove(_key);
    final foundKeys = _prefs.getKeys()
        .where((k) => k.startsWith(_foundPrefix))
        .toList();
    for (final key in foundKeys) {
      await _prefs.remove(key);
    }
    _foundWords.clear();
    notifyListeners();
  }
}
