import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/level.dart';

/// Service to fetch level candidates from Firestore for test mode.
///
/// Documents in the `garble_candidates` collection should have:
/// - `garble`: String - the garbled word
/// - `words`: List of strings - valid words that can be found
/// - `createdAt`: Timestamp - when the level was generated
class CandidateService {
  static final CandidateService instance = CandidateService._();
  CandidateService._();

  final _firestore = FirebaseFirestore.instance;
  static const _collection = 'garble_candidates';

  List<Level>? _cachedLevels;
  bool _isLoading = false;

  /// Fetch all candidate levels from Firestore.
  ///
  /// Results are cached after first fetch. Call [refresh] to reload.
  Future<List<Level>> fetchLevels() async {
    if (_cachedLevels != null) return _cachedLevels!;
    if (_isLoading) {
      // Wait for current load to complete
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cachedLevels ?? [];
    }

    _isLoading = true;
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .orderBy('createdAt', descending: false)
          .get();

      _cachedLevels = snapshot.docs.asMap().entries.map((entry) {
        final index = entry.key;
        final doc = entry.value;
        final data = doc.data();

        final garble = data['garble'] as String;
        final wordsRaw = data['words'] as List<dynamic>?;
        final words = wordsRaw?.cast<String>().toSet();

        return Level(
          number: index + 1, // 1-indexed
          garble: garble,
          words: words,
          firestoreId: doc.id,
        );
      }).toList();

      return _cachedLevels!;
    } finally {
      _isLoading = false;
    }
  }

  /// Force refresh levels from Firestore.
  Future<List<Level>> refresh() async {
    _cachedLevels = null;
    return fetchLevels();
  }

  /// Clear cache.
  void clearCache() {
    _cachedLevels = null;
  }

  /// Get count of levels (fetches if not cached).
  Future<int> get levelCount async {
    final levels = await fetchLevels();
    return levels.length;
  }
}
