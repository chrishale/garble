import 'dart:io';

import 'package:garble/core/garble_merger.dart';

// Merge two words using maximum overlap strategy.
//
// Usage: dart run garble:create_garble <word1> <word2>
void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run garble:create_garble <word1> <word2>');
    stderr.writeln('Example: dart run garble:create_garble TRAIN RAINS');
    exit(1);
  }

  final word1 = args[0].toUpperCase();
  final word2 = args[1].toUpperCase();

  const merger = GarbleMerger();
  final result = merger.merge(word1, word2);
  final overlap = merger.overlapLength(word1, word2);

  stdout.writeln('Word 1:  $word1');
  stdout.writeln('Word 2:  $word2');
  stdout.writeln('Overlap: $overlap character${overlap == 1 ? '' : 's'}');
  stdout.writeln('Result:  $result');

  if (overlap == 0) {
    stdout.writeln();
    stdout.writeln('No overlap found - words were concatenated.');
  }
}
