import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// VAXtrust 로고. 이미지 파일이 없어도 앱에서 바로 그립니다.
class VaxLogo extends StatelessWidget {
  const VaxLogo({super.key, this.compact = false, this.light = false});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final Color markColor = light ? Colors.white : AppColors.navy;
    final Color accent = light ? AppColors.mint : AppColors.teal;
    final double size = compact ? 36 : 64;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: light ? Colors.white.withValues(alpha: 0.12) : AppColors.ice,
            borderRadius: BorderRadius.circular(size * 0.28),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 1.4,
            ),
          ),
          child: Icon(Icons.ac_unit, color: accent, size: size * 0.58),
        ),
        SizedBox(width: compact ? 10 : 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'VAX',
                    style: TextStyle(
                      fontSize: compact ? 20 : 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: markColor,
                    ),
                  ),
                  TextSpan(
                    text: 'trust',
                    style: TextStyle(
                      fontSize: compact ? 20 : 28,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            if (!compact)
              Text(
                'VACCINE COLD CHAIN',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w600,
                  color: light
                      ? Colors.white.withValues(alpha: 0.72)
                      : AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
