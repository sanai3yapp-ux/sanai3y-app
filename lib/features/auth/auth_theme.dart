import 'package:flutter/material.dart';

/// الهوية البصرية الموحدة لشاشات تسجيل الدخول والتسجيل في تطبيق صنايعي.
abstract final class Sanai3yAuthTheme {
  // الألوان الأساسية
  static const Color navy = Color(0xFF062E49);
  static const Color blue = Color(0xFF0878BD);
  static const Color blueDark = Color(0xFF006BB3);
  static const Color blueSoft = Color(0xFFF0F8FF);
  static const Color blueBorder = Color(0xFF9FD5F5);
  static const Color gold = Color(0xFFF2A800);
  static const Color goldSoft = Color(0xFFFFF7E6);
  static const Color textSecondary = Color(0xFF55758D);
  static const Color pageBackground = Color(0xFFF8F9FC);
  static const Color white = Colors.white;

  // أحجام الحواف
  static const double cardRadius = 22;
  static const double fieldRadius = 16;
  static const double buttonRadius = 17;

  // مسافات الصفحات
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 24,
  );

  // شكل الكارت
  static BoxDecoration authCardDecoration({
    bool gold = false,
  }) {
    return BoxDecoration(
      color: gold ? goldSoft : white,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: gold ? const Color(0xFFF4D58A) : blueBorder,
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  // شكل خانات الإدخال
  static InputDecoration fieldDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: white,

      labelStyle: const TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w600,
      ),

      hintStyle: const TextStyle(
        color: Color(0xFF9AAEBC),
      ),

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(
          color: Color(0xFFD7E5EF),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(
          color: Color(0xFFD7E5EF),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(
          color: blue,
          width: 1.8,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.5,
        ),
      ),
    );
  }

  // الزر الرئيسي
  static ButtonStyle primaryButtonStyle({
    bool gold = false,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: gold
          ? Sanai3yAuthTheme.gold
          : Sanai3yAuthTheme.blue,
      foregroundColor: white,
      minimumSize: const Size(
        double.infinity,
        54,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
      ),
      textStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // عنوان الصفحة
  static TextStyle titleStyle({
    double size = 27,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.bold,
      color: navy,
      height: 1.2,
    );
  }

  // النص الثانوي
  static TextStyle subtitleStyle({
    double size = 14,
  }) {
    return TextStyle(
      fontSize: size,
      color: textSecondary,
      height: 1.5,
    );
  }

  // عنوان القسم
  static TextStyle sectionLabelStyle() {
    return const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: navy,
    );
  }
}