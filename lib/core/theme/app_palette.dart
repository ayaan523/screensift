import 'package:flutter/material.dart';

/// Single source of truth for the ScreenSift colour system.
///
/// The product palette is deliberately narrow: a clean white canvas, a single
/// teal accent that carries every interactive affordance, and a dark slate
/// family for text and high-contrast surfaces.
abstract final class AppPalette {
  // --- Brand ---------------------------------------------------------------
  static const Color teal = Color(0xFF0D9488);
  static const Color tealDark = Color(0xFF0F766E);
  static const Color tealDeep = Color(0xFF115E59);
  static const Color tealTint = Color(0xFFE6F5F3);
  static const Color tealTintStrong = Color(0xFFCCEDE8);

  // --- Slate ---------------------------------------------------------------
  static const Color slate = Color(0xFF0F172A);
  static const Color slateSoft = Color(0xFF1E293B);
  static const Color slateMuted = Color(0xFF64748B);
  static const Color slateFaint = Color(0xFF94A3B8);

  // --- Canvas --------------------------------------------------------------
  static const Color white = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color canvasAlt = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  // --- Accent --------------------------------------------------------------
  // A single warm accent. It is reserved for capture affordances (the FAB and
  // the in-flight indicator) so "something is being scanned" is unmistakable
  // against the otherwise teal-and-slate UI.
  static const Color accent = Color(0xFFFF7A45);
  static const Color accentDark = Color(0xFFE85D26);
  static const Color accentTint = Color(0xFFFFEDE4);

  // --- Gradients -----------------------------------------------------------
  /// Page background. Replaces the hardcoded `0xFFF0F9F8` that used to sit on
  /// the shell's Scaffold and drifted from the rest of the palette.
  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF0FBF9), canvas],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, tealDeep],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDark],
  );

  // --- Semantic ------------------------------------------------------------
  static const Color success = Color(0xFF16A34A);
  static const Color successTint = Color(0xFFE8F7EE);
  static const Color warning = Color(0xFFD97706);
  static const Color warningTint = Color(0xFFFDF3E4);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerTint = Color(0xFFFDECEC);
  static const Color info = Color(0xFF2563EB);
  static const Color infoTint = Color(0xFFE9EFFD);
}
