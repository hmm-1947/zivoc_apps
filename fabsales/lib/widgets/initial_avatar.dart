import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.text, this.size = 44});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accents = context.appColors.avatarAccents;
    final seed = text.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final accent = accents[seed % accents.length];

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.14),
        ),
        child: Center(
          child: Text(
            initialsOf(text),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.34,
            ),
          ),
        ),
      ),
    );
  }
}
