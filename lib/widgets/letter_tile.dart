import 'package:flutter/material.dart';

class LetterTile extends StatelessWidget {
  final String letter;
  final VoidCallback? onTap;
  final bool highlighted;
  final double size;

  const LetterTile({
    super.key,
    required this.letter,
    this.onTap,
    this.highlighted = false,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlighted ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = highlighted ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final radius = size * 0.22;
    final fontSize = size * 0.5;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: size,
          height: size * (64 / 56),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}
