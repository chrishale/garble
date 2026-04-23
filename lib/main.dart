import 'package:flutter/material.dart';

import 'data/levels.dart';
import 'screens/level_select_screen.dart';
import 'services/progress.dart';
import 'services/scorer.dart';

void main() {
  runApp(const GarbleApp());
}

class GarbleApp extends StatelessWidget {
  const GarbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFFB020),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Garble',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E0F13),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF0E0F13),
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  Progress? _progress;
  String? _error;

  static const _scorer = Scorer();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      for (final level in kLevels) {
        level.maxScore = _scorer.maxScore(level.garble, level.words);
      }
      final progress = await Progress.load();
      if (!mounted) return;
      setState(() => _progress = progress);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
      );
    }
    if (_progress == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return LevelSelectScreen(scorer: _scorer, progress: _progress!);
  }
}
