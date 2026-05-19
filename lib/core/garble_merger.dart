/// Merges two words using maximum suffix-prefix overlap strategy.
class GarbleMerger {
  const GarbleMerger();

  /// Merge [word1] and [word2] using maximum overlap strategy.
  ///
  /// Finds the longest suffix of word1 that matches a prefix of word2,
  /// then concatenates word1 + remaining portion of word2.
  ///
  /// Examples:
  /// - merge("TRAIN", "RAINS") → "TRAINS" (4-char overlap: "RAIN")
  /// - merge("CAT", "DOG") → "CATDOG" (0-char overlap)
  /// - merge("CASTLE", "LE") → "CASTLE" (2-char overlap: "LE")
  String merge(String word1, String word2) {
    final w1 = word1.toUpperCase();
    final w2 = word2.toUpperCase();

    final overlap = overlapLength(w1, w2);
    return w1 + w2.substring(overlap);
  }

  /// Returns the overlap length between suffix of [word1] and prefix of [word2].
  ///
  /// Finds the longest suffix of word1 that matches a prefix of word2.
  int overlapLength(String word1, String word2) {
    final w1 = word1.toUpperCase();
    final w2 = word2.toUpperCase();

    final maxOverlap = w1.length < w2.length ? w1.length : w2.length;

    for (var overlap = maxOverlap; overlap > 0; overlap--) {
      if (w1.substring(w1.length - overlap) == w2.substring(0, overlap)) {
        return overlap;
      }
    }
    return 0;
  }
}
