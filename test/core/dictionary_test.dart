import 'package:flutter_test/flutter_test.dart';
import 'package:garble/core/dictionary.dart';

void main() {
  group('Dictionary', () {
    test('parses words from text', () {
      final dict = Dictionary.fromText('CAT\nDOG\nBIRD');
      expect(dict.length, 3);
      expect(dict.contains('CAT'), isTrue);
      expect(dict.contains('DOG'), isTrue);
      expect(dict.contains('BIRD'), isTrue);
    });

    test('normalizes to uppercase', () {
      final dict = Dictionary.fromText('cat\nDOG\nBird');
      expect(dict.contains('CAT'), isTrue);
      expect(dict.contains('cat'), isTrue);
      expect(dict.contains('Cat'), isTrue);
    });

    test('ignores empty lines', () {
      final dict = Dictionary.fromText('CAT\n\nDOG\n\n');
      expect(dict.length, 2);
    });

    test('ignores comment lines starting with #', () {
      final dict = Dictionary.fromText('# This is a comment\nCAT\n# Another comment\nDOG');
      expect(dict.length, 2);
      expect(dict.contains('#'), isFalse);
    });

    test('trims whitespace', () {
      final dict = Dictionary.fromText('  CAT  \n  DOG  ');
      expect(dict.contains('CAT'), isTrue);
      expect(dict.contains('DOG'), isTrue);
    });

    test('handles empty input', () {
      final dict = Dictionary.fromText('');
      expect(dict.length, 0);
    });

    test('handles Windows line endings', () {
      final dict = Dictionary.fromText('CAT\r\nDOG\r\nBIRD');
      expect(dict.length, 3);
    });
  });
}
