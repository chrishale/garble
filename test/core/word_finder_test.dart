import 'package:flutter_test/flutter_test.dart';
import 'package:garble/core/dictionary.dart';
import 'package:garble/core/word_finder.dart';

void main() {
  group('WordFinder', () {
    test('finds exact match', () {
      final dict = Dictionary.fromText('CAT\nDOG');
      final finder = WordFinder(dict);
      expect(finder.findWords('CAT'), contains('CAT'));
    });

    test('finds subsequences', () {
      final dict = Dictionary.fromText('CAT\nBAT\nA\nAT');
      final finder = WordFinder(dict);
      final words = finder.findWords('BCATS');
      expect(words, containsAll(['CAT', 'BAT', 'A', 'AT']));
    });

    test('respects order (not permutation)', () {
      final dict = Dictionary.fromText('TAC'); // reversed CAT
      final finder = WordFinder(dict);
      expect(finder.findWords('CAT'), isEmpty);
    });

    test('handles empty garble', () {
      final dict = Dictionary.fromText('CAT');
      final finder = WordFinder(dict);
      expect(finder.findWords(''), isEmpty);
    });

    test('handles empty dictionary', () {
      final dict = Dictionary.fromText('');
      final finder = WordFinder(dict);
      expect(finder.findWords('CAT'), isEmpty);
    });

    test('is case insensitive', () {
      final dict = Dictionary.fromText('cat\nDOG');
      final finder = WordFinder(dict);
      expect(finder.findWords('Cat'), containsAll(['CAT']));
    });

    test('finds multiple length subsequences', () {
      final dict = Dictionary.fromText('A\nAS\nAT\nBAT\nBATS\nCAT\nCATS');
      final finder = WordFinder(dict);
      final words = finder.findWords('BCATS');
      expect(words, containsAll(['A', 'AS', 'AT', 'BAT', 'BATS', 'CAT', 'CATS']));
    });

    test('does not find words longer than garble', () {
      final dict = Dictionary.fromText('CATASTROPHE');
      final finder = WordFinder(dict);
      expect(finder.findWords('CAT'), isEmpty);
    });
  });

  group('WordFinder.isSubsequence', () {
    test('exact match is subsequence', () {
      expect(WordFinder.isSubsequence('CAT', 'CAT'), isTrue);
    });

    test('skipping letters is valid', () {
      expect(WordFinder.isSubsequence('CAT', 'BCATS'), isTrue);
      expect(WordFinder.isSubsequence('BAT', 'BCATS'), isTrue);
    });

    test('reversed order is not subsequence', () {
      expect(WordFinder.isSubsequence('TAC', 'CAT'), isFalse);
    });

    test('empty word is subsequence', () {
      expect(WordFinder.isSubsequence('', 'CAT'), isTrue);
    });

    test('longer word cannot be subsequence', () {
      expect(WordFinder.isSubsequence('CATASTROPHE', 'CAT'), isFalse);
    });
  });
}
