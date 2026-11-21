import 'package:flutter/material.dart';

/// 앱 전체에서 쓰는 색과 스타일을 한곳에 모아 둡니다.
/// 화면마다 색을 따로 적으면 나중에 바꾸기 어렵기 때문입니다.
class AppColors {
  static const Color navy = Color(0xFF0B2E3A);
  static const Color teal = Color(0xFF0F5C66);
  static const Color mint = Color(0xFF2BBBAD);
  static const Color ice = Color(0xFFF3F7F8);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF102A33);
  static const Color textSecondary = Color(0xFF5B717A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFC24141);
  static const Color success = Color(0xFF1F8A6E);
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.ice,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        surface: AppColors.card,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(height: 1.45, color: AppColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: AppColors.teal,
          side: const BorderSide(color: AppColors.teal),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          foregroundColor: AppColors.teal,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
