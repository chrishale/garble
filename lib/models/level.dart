class Level {
  final int number;
  final String garble;
  final Set<String> words;
  int? maxScore;

  Level({
    required this.number,
    required this.garble,
    required this.words,
  });

  String get id => 'L$number';
}
