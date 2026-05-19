import 'dictionary.dart';

/// Finds valid dictionary words that are subsequences of a garble string.
/// A subsequence maintains relative order but may skip characters.
class WordFinder {
  final Dictionary dictionary;

  const WordFinder(this.dictionary);

  /// Returns all dictionary words that are subsequences of [garble].
  ///
  /// Example: findWords("BCATS") might return {"A", "AS", "AT", "BAT", "BATS", "CAT", "CATS"}
  Set<String> findWords(String garble) {
    final garbleUpper = garble.toUpperCase();
    final result = <String>{};

    for (final word in dictionary.words) {
      if (word.length > garbleUpper.length) continue;
      if (isSubsequence(word, garbleUpper)) {
        result.add(word);
      }
    }

    return result;
  }

  /// Returns true if [word] is a subsequence of [garble].
  ///
  /// A subsequence preserves order but may skip characters:
  /// - "CAT" is a subsequence of "BCATS" (B-C-A-T-S)
  /// - "TAC" is NOT a subsequence of "CAT" (wrong order)
  static bool isSubsequence(String word, String garble) {
    var wordIdx = 0;
    for (var i = 0; i < garble.length && wordIdx < word.length; i++) {
      if (garble[i] == word[wordIdx]) {
        wordIdx++;
      }
    }
    return wordIdx == word.length;
  }
}
