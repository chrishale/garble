import 'package:flutter/services.dart' show rootBundle;

import '../core/dictionary.dart';
import '../core/word_finder.dart';
import 'locale_service.dart';

/// Service for loading and querying Scrabble dictionaries.
class DictionaryService {
  Dictionary? _dictionary;
  DictionaryLocale? _loadedLocale;

  static const _assetPaths = {
    DictionaryLocale.us: 'assets/dictionaries/twl06.txt',
    DictionaryLocale.uk: 'assets/dictionaries/sowpods.txt',
  };

  /// The currently loaded dictionary, or null if not loaded.
  Dictionary? get dictionary => _dictionary;

  /// The locale of the currently loaded dictionary.
  DictionaryLocale? get loadedLocale => _loadedLocale;

  /// Load dictionary for the given locale. Caches result.
  Future<Dictionary> load(DictionaryLocale locale) async {
    if (_dictionary != null && _loadedLocale == locale) {
      return _dictionary!;
    }

    final path = _assetPaths[locale]!;
    final content = await rootBundle.loadString(path);
    _dictionary = Dictionary.fromText(content);
    _loadedLocale = locale;
    return _dictionary!;
  }

  /// Find all valid words for a garble string using loaded dictionary.
  ///
  /// Throws [StateError] if dictionary not loaded.
  Set<String> findWordsForGarble(String garble) {
    if (_dictionary == null) {
      throw StateError('Dictionary not loaded. Call load() first.');
    }
    return WordFinder(_dictionary!).findWords(garble);
  }

  /// Check if a word exists in the loaded dictionary.
  bool isValidWord(String word) {
    if (_dictionary == null) return false;
    return _dictionary!.contains(word);
  }
}
