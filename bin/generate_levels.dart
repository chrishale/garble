import 'dart:io';
import 'dart:math';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart' as admin;
import 'package:garble/core/dictionary.dart';
import 'package:garble/core/garble_merger.dart';
import 'package:garble/core/word_finder.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

// Generate level candidates from dictionary intersection.
//
// Usage: dart run garble:generate_levels [options]
// Options:
//   --max-length=N    Maximum word length for base words (default: 6)
//   --top=N           Number of top candidates to output (default: 100)
//   --min-overlap=N   Minimum overlap required (default: 2)
//   --output=FILE     Output file path (default: stdout)
//   --upload          Upload to Firestore garble_candidates collection
//   --credentials=FILE Path to Firebase service account JSON
//   --seed=N          Random seed for deterministic shuffling
//   --skip-existing   Skip garbles that already exist in Firestore

class WordPair {
  final String word1;
  final String word2;
  final String garble;
  final int overlap;

  const WordPair({
    required this.word1,
    required this.word2,
    required this.garble,
    required this.overlap,
  });
}

void main(List<String> args) async {
  // Parse arguments
  var maxLength = 6;
  var topCount = 100;
  var minOverlap = 2;
  String? outputPath;
  var upload = false;
  String? credentialsPath;
  int? seed;
  var skipExisting = false;

  for (final arg in args) {
    if (arg.startsWith('--max-length=')) {
      maxLength = int.parse(arg.substring(13));
    } else if (arg.startsWith('--top=')) {
      topCount = int.parse(arg.substring(6));
    } else if (arg.startsWith('--min-overlap=')) {
      minOverlap = int.parse(arg.substring(14));
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring(9);
    } else if (arg == '--upload') {
      upload = true;
    } else if (arg.startsWith('--credentials=')) {
      credentialsPath = arg.substring(14);
    } else if (arg.startsWith('--seed=')) {
      seed = int.parse(arg.substring(7));
    } else if (arg == '--skip-existing') {
      skipExisting = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      exit(0);
    }
  }

  // Validate upload requirements
  if (upload && credentialsPath == null) {
    stderr.writeln('Error: --upload requires --credentials=FILE');
    exit(1);
  }

  stderr.writeln('Level Generator');
  stderr.writeln('===============');
  stderr.writeln('Max word length: $maxLength');
  stderr.writeln('Top candidates: $topCount');
  stderr.writeln('Min overlap: $minOverlap');
  if (seed != null) stderr.writeln('Random seed: $seed');
  if (upload) stderr.writeln('Upload to Firestore: enabled');
  if (skipExisting) stderr.writeln('Skip existing: enabled');
  stderr.writeln();

  // Initialize Firestore if needed
  admin.FirebaseApp? firebaseApp;
  Firestore? firestore;
  Set<String> existingGarbles = {};

  if (upload || skipExisting) {
    if (credentialsPath == null) {
      stderr.writeln('Error: --credentials required for Firestore operations');
      exit(1);
    }

    stderr.writeln('Initializing Firebase...');
    final credFile = File(credentialsPath);
    if (!credFile.existsSync()) {
      stderr.writeln('Error: Credentials file not found: $credentialsPath');
      exit(1);
    }

    firebaseApp = admin.FirebaseApp.initializeApp(
      options: admin.AppOptions(
        credential: admin.Credential.fromServiceAccount(credFile),
        projectId: 'garble-f1095',
      ),
    );
    firestore = firebaseApp.firestore();

    if (skipExisting) {
      stderr.writeln('Fetching existing garbles from Firestore...');
      final snapshot = await firestore.collection('garble_candidates').get();
      existingGarbles = snapshot.docs
          .map((doc) => doc.data()['garble'] as String?)
          .whereType<String>()
          .toSet();
      stderr.writeln('  Found ${existingGarbles.length} existing garbles');
    }
  }

  // Load dictionaries
  stderr.writeln('Loading dictionaries...');
  final twl06File = File('assets/dictionaries/twl06.txt');
  final sowpodsFile = File('assets/dictionaries/sowpods.txt');

  if (!twl06File.existsSync() || !sowpodsFile.existsSync()) {
    stderr.writeln('Error: Dictionary files not found.');
    stderr.writeln('Make sure you run this from the project root directory.');
    exit(1);
  }

  final twl06 = Dictionary.fromText(await twl06File.readAsString());
  final sowpods = Dictionary.fromText(await sowpodsFile.readAsString());

  stderr.writeln('  TWL06: ${twl06.length} words');
  stderr.writeln('  SOWPODS: ${sowpods.length} words');

  // Combined dictionary for filtering out garbles that are valid words
  final allWords = twl06.words.union(sowpods.words);
  stderr.writeln('  Combined: ${allWords.length} unique words');

  // Find common words within length limit
  stderr.writeln('Finding common words (length <= $maxLength)...');
  final commonWords = twl06.words
      .intersection(sowpods.words)
      .where((w) => w.length <= maxLength && w.length >= 2)
      .toList()
    ..sort();

  stderr.writeln('  Found ${commonWords.length} common words');

  // Generate all pairs with overlap
  stderr.writeln('Generating word pairs...');
  const merger = GarbleMerger();
  final garbleToBestPair = <String, WordPair>{};

  var pairsProcessed = 0;
  var garblesFilteredAsWords = 0;
  var garblesFilteredAsExisting = 0;
  final totalPairs = commonWords.length * (commonWords.length - 1);
  var lastProgressPercent = -1;

  for (final w1 in commonWords) {
    for (final w2 in commonWords) {
      if (w1 == w2) continue;

      final overlap = merger.overlapLength(w1, w2);
      if (overlap < minOverlap) {
        pairsProcessed++;
        continue;
      }

      final garble = merger.merge(w1, w2);

      // Skip garbles that are valid dictionary words
      if (allWords.contains(garble)) {
        garblesFilteredAsWords++;
        pairsProcessed++;
        continue;
      }

      // Skip garbles that already exist in Firestore
      if (skipExisting && existingGarbles.contains(garble)) {
        garblesFilteredAsExisting++;
        pairsProcessed++;
        continue;
      }

      final pair = WordPair(
        word1: w1,
        word2: w2,
        garble: garble,
        overlap: overlap,
      );

      // Keep the pair with highest overlap for each garble
      final existing = garbleToBestPair[garble];
      if (existing == null || pair.overlap > existing.overlap) {
        garbleToBestPair[garble] = pair;
      }

      pairsProcessed++;

      // Progress indicator
      final progressPercent = (pairsProcessed * 100) ~/ totalPairs;
      if (progressPercent != lastProgressPercent && progressPercent % 10 == 0) {
        stderr.writeln('  Progress: $progressPercent%');
        lastProgressPercent = progressPercent;
      }
    }
  }

  stderr.writeln('  Garbles filtered (valid words): $garblesFilteredAsWords');
  if (skipExisting) {
    stderr.writeln('  Garbles filtered (existing): $garblesFilteredAsExisting');
  }
  stderr.writeln('  Unique garbles: ${garbleToBestPair.length}');

  // Sort by overlap descending, then apply random shuffle with seed
  var sortedPairs = garbleToBestPair.values.toList()
    ..sort((a, b) {
      // Primary: overlap descending
      final overlapCmp = b.overlap.compareTo(a.overlap);
      if (overlapCmp != 0) return overlapCmp;
      // Secondary: garble length ascending (prefer shorter)
      final lengthCmp = a.garble.length.compareTo(b.garble.length);
      if (lengthCmp != 0) return lengthCmp;
      // Tertiary: alphabetical
      return a.garble.compareTo(b.garble);
    });

  // Group by overlap level and shuffle within each group for variety
  if (seed != null) {
    final random = Random(seed);
    final byOverlap = <int, List<WordPair>>{};
    for (final pair in sortedPairs) {
      byOverlap.putIfAbsent(pair.overlap, () => []).add(pair);
    }

    // Shuffle each overlap group
    for (final group in byOverlap.values) {
      group.shuffle(random);
    }

    // Rebuild sorted list maintaining overlap order
    final sortedEntries = byOverlap.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final shuffled = <WordPair>[];
    for (final entry in sortedEntries) {
      shuffled.addAll(entry.value);
    }
    sortedPairs = shuffled;
  }

  final topCandidates = sortedPairs.take(topCount).toList();
  stderr.writeln('Selected top ${topCandidates.length} candidates');

  // Find words for each garble
  stderr.writeln('Finding words for each garble...');
  final finder = WordFinder(twl06);

  final candidatesWithWords = <({WordPair pair, Set<String> words})>[];
  for (final pair in topCandidates) {
    final words = finder.findWords(pair.garble);
    candidatesWithWords.add((pair: pair, words: words));
  }

  // Upload to Firestore if requested
  if (upload && firestore != null) {
    stderr.writeln('Uploading ${candidatesWithWords.length} levels to Firestore...');
    var uploaded = 0;
    var skipped = 0;

    for (final candidate in candidatesWithWords) {
      // Check if already exists (double-check even if skipExisting was used)
      final existing = await firestore
          .collection('garble_candidates')
          .where('garble', WhereFilter.equal, candidate.pair.garble)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        skipped++;
        continue;
      }

      // Upload new candidate
      await firestore.collection('garble_candidates').add({
        'garble': candidate.pair.garble,
        'words': candidate.words.toList()..sort(),
        'sourceWord1': candidate.pair.word1,
        'sourceWord2': candidate.pair.word2,
        'overlap': candidate.pair.overlap,
        'createdAt': FieldValue.serverTimestamp,
      });
      uploaded++;

      if (uploaded % 10 == 0) {
        stderr.writeln('  Uploaded $uploaded levels...');
      }
    }

    stderr.writeln('  Uploaded: $uploaded');
    stderr.writeln('  Skipped (already exist): $skipped');
  }

  // Generate Dart code output if not upload-only
  if (outputPath != null || !upload) {
    stderr.writeln('Generating Dart code...');

    final output = StringBuffer();
    output.writeln("import '../models/level.dart';");
    output.writeln();
    output.writeln('/// Generated levels from dictionary intersection.');
    output.writeln('/// Generated with: dart run garble:generate_levels '
        '--max-length=$maxLength --top=$topCount --min-overlap=$minOverlap'
        '${seed != null ? ' --seed=$seed' : ''}');
    output.writeln('final List<Level> kGeneratedLevels = [');

    for (var i = 0; i < candidatesWithWords.length; i++) {
      final candidate = candidatesWithWords[i];
      final pair = candidate.pair;
      final levelNum = i + 1;

      final sortedWords = candidate.words.toList()..sort();

      output.writeln('  // Level $levelNum: ${pair.word1} + ${pair.word2} '
          '(overlap: ${pair.overlap})');
      output.writeln('  Level(');
      output.writeln('    number: $levelNum,');
      output.writeln("    garble: '${pair.garble}',");
      output.writeln('    words: {');
      for (final word in sortedWords) {
        output.writeln("      '$word',");
      }
      output.writeln('    },');
      output.writeln('  ),');
    }

    output.writeln('];');

    // Write output
    if (outputPath != null) {
      await File(outputPath).writeAsString(output.toString());
      stderr.writeln('Output written to: $outputPath');
    } else if (!upload) {
      stdout.write(output.toString());
    }
  }

  stderr.writeln('Done!');
}

void _printUsage() {
  stderr.writeln('Generate level candidates from dictionary intersection.');
  stderr.writeln();
  stderr.writeln('Usage: dart run garble:generate_levels [options]');
  stderr.writeln();
  stderr.writeln('Options:');
  stderr.writeln('  --max-length=N     Maximum word length for base words (default: 6)');
  stderr.writeln('  --top=N            Number of top candidates to output (default: 100)');
  stderr.writeln('  --min-overlap=N    Minimum overlap required (default: 2)');
  stderr.writeln('  --output=FILE      Output file path (default: stdout)');
  stderr.writeln('  --upload           Upload to Firestore garble_candidates collection');
  stderr.writeln('  --credentials=FILE Path to Firebase service account JSON');
  stderr.writeln('  --seed=N           Random seed for deterministic shuffling');
  stderr.writeln('  --skip-existing    Skip garbles that already exist in Firestore');
  stderr.writeln('  --help, -h         Show this help message');
  stderr.writeln();
  stderr.writeln('Examples:');
  stderr.writeln('  # Generate 50 levels and upload to Firestore');
  stderr.writeln('  dart run garble:generate_levels --top=50 --upload --credentials=./service-account.json');
  stderr.writeln();
  stderr.writeln('  # Generate with random seed (reproducible but varied order)');
  stderr.writeln('  dart run garble:generate_levels --seed=12345 --top=100');
  stderr.writeln();
  stderr.writeln('  # Add new levels to existing collection');
  stderr.writeln('  dart run garble:generate_levels --top=50 --upload --skip-existing --credentials=./service-account.json');
}
