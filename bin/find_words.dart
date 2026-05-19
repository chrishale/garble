import 'dart:io';

import 'package:garble/core/dictionary.dart';
import 'package:garble/core/word_finder.dart';

// Find all valid Scrabble words from a garble string.
//
// Usage: dart run garble:find_words <garble> [--dict=us|uk]
void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run garble:find_words <garble> [--dict=us|uk]');
    stderr.writeln('Example: dart run garble:find_words BCATS');
    exit(1);
  }

  final garble = args[0].toUpperCase();

  // Parse --dict flag (default: us)
  var dictPath = 'assets/dictionaries/twl06.txt';
  var dictName = 'US (TWL06)';
  for (final arg in args.skip(1)) {
    if (arg.startsWith('--dict=')) {
      final value = arg.substring(7).toLowerCase();
      if (value == 'uk') {
        dictPath = 'assets/dictionaries/sowpods.txt';
        dictName = 'UK (SOWPODS)';
      }
    }
  }

  // Load dictionary from file (CLI uses dart:io, not rootBundle)
  final file = File(dictPath);
  if (!file.existsSync()) {
    stderr.writeln('Dictionary not found: $dictPath');
    stderr.writeln('Make sure you run this from the project root directory.');
    exit(1);
  }

  final content = await file.readAsString();
  final dictionary = Dictionary.fromText(content);
  final finder = WordFinder(dictionary);

  final words = finder.findWords(garble);
  final sorted = words.toList()
    ..sort((a, b) {
      // Sort by length descending, then alphabetically
      final lenCmp = b.length.compareTo(a.length);
      return lenCmp != 0 ? lenCmp : a.compareTo(b);
    });

  stdout.writeln('Dictionary: $dictName (${dictionary.length} words)');
  stdout.writeln('Garble: $garble');
  stdout.writeln('Found ${sorted.length} valid words:');
  stdout.writeln();

  // Group by length
  var currentLength = 0;
  for (final word in sorted) {
    if (word.length != currentLength) {
      currentLength = word.length;
      stdout.writeln('  --- $currentLength letters ---');
    }
    stdout.writeln('  $word');
  }
}
