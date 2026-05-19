import 'package:flutter_test/flutter_test.dart';
import 'package:garble/core/garble_merger.dart';

void main() {
  const merger = GarbleMerger();

  group('GarbleMerger.merge', () {
    test('TRAIN + RAINS = TRAINS', () {
      expect(merger.merge('TRAIN', 'RAINS'), 'TRAINS');
    });

    test('no overlap concatenates', () {
      expect(merger.merge('CAT', 'DOG'), 'CATDOG');
    });

    test('full overlap (word2 is suffix)', () {
      expect(merger.merge('CASTLE', 'LE'), 'CASTLE');
    });

    test('case insensitive', () {
      expect(merger.merge('Train', 'rains'), 'TRAINS');
    });

    test('single character overlap', () {
      expect(merger.merge('ABC', 'CDE'), 'ABCDE');
    });

    test('word1 equals word2', () {
      expect(merger.merge('CAT', 'CAT'), 'CAT');
    });

    test('word2 is prefix of word1 suffix', () {
      expect(merger.merge('STEAM', 'EAM'), 'STEAM');
    });
  });

  group('GarbleMerger.overlapLength', () {
    test('TRAIN + RAINS = 4', () {
      expect(merger.overlapLength('TRAIN', 'RAINS'), 4);
    });

    test('no overlap returns 0', () {
      expect(merger.overlapLength('CAT', 'DOG'), 0);
    });

    test('full overlap returns word2 length', () {
      expect(merger.overlapLength('CASTLE', 'LE'), 2);
    });

    test('word1 equals word2 returns full length', () {
      expect(merger.overlapLength('CAT', 'CAT'), 3);
    });

    test('single character overlap', () {
      expect(merger.overlapLength('ABC', 'CDE'), 1);
    });

    test('case insensitive', () {
      expect(merger.overlapLength('train', 'RAINS'), 4);
    });
  });
}
