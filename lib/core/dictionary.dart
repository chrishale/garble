/// Pure Dart dictionary abstraction for word lookup.
/// No Flutter dependencies - can be used by CLI and app.
class Dictionary {
  final Set<String> words;

  const Dictionary._(this.words);

  /// Create a dictionary from raw text content (one word per line).
  /// Lines starting with # are treated as comments.
  /// Words are normalized to uppercase.
  factory Dictionary.fromText(String content) {
    final words = content
        .split('\n')
        .map((line) => line.trim().toUpperCase())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();
    return Dictionary._(words);
  }

  /// Check if a word exists in the dictionary (case-insensitive).
  bool contains(String word) => words.contains(word.toUpperCase());

  /// Number of words in the dictionary.
  int get length => words.length;
}
