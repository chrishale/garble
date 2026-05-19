class Level {
  final int number;
  final String garble;

  /// Firestore document ID (for candidate levels from Firestore).
  final String? firestoreId;

  /// Explicit word set. If null or empty, words are derived from dictionary.
  final Set<String>? _explicitWords;

  /// Lazily populated from dictionary when _explicitWords is null/empty.
  Set<String>? _derivedWords;

  int? maxScore;

  Level({
    required this.number,
    required this.garble,
    Set<String>? words,
    this.firestoreId,
  }) : _explicitWords = words;

  /// Returns true if this level uses dictionary-derived words.
  bool get usesDictionary {
    final words = _explicitWords;
    return words == null || words.isEmpty;
  }

  /// The word set for this level.
  ///
  /// For levels with explicit words, returns those words.
  /// For levels using dictionary, must call [initializeWords] first.
  Set<String> get words {
    if (!usesDictionary) return _explicitWords!;
    if (_derivedWords == null) {
      throw StateError(
        'Level $number uses dictionary but words not initialized. '
        'Call Level.initializeWords() during app startup.',
      );
    }
    return _derivedWords!;
  }

  /// Initialize derived words from dictionary. No-op if level has explicit words.
  void initializeWords(Set<String> dictionaryWords) {
    if (!usesDictionary) return;
    _derivedWords = dictionaryWords;
  }

  String get id => 'L$number';
}
