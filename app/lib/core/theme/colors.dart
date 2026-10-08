import 'package:flutter/material.dart';

/// Lovebird palette. Pink carries identity & action; warm neutrals carry text.
/// All text/background pairs below meet WCAG AA (≥ 4.5:1) — pink is never body text on cream.
class LBColors {
  // Brand pinks
  static const rose = Color(0xFFC2185B); // primary action (5.9:1 with white)
  static const roseDeep = Color(0xFF8E0E43); // pressed / emphasis
  static const blossom = Color(0xFFF06292); // accents, hearts, illustrations (not text on light)
  static const petal = Color(0xFFF8BBD0); // soft fills, chips
  static const blush = Color(0xFFFDE7EF); // tinted surfaces
  static const mist = Color(0xFFFFF5F8); // page wash

  // Warm neutrals
  static const cream = Color(0xFFFFFBF9);
  static const ink = Color(0xFF2A1520); // plum-ink body text (15:1 on cream)
  static const inkSoft = Color(0xFF6B5360); // secondary text (6.6:1 on cream)
  static const line = Color(0xFFEFDDE4);

  // Supporting
  static const peach = Color(0xFFFFB199);
  static const lilac = Color(0xFFB39DDB);
  static const mint = Color(0xFF7FCBA8);
  static const gold = Color(0xFFE8B04B);
  static const danger = Color(0xFFB3261E);
  static const success = Color(0xFF2E7D5B);

  // Dark mode
  static const night = Color(0xFF170D12);
  static const nightSurface = Color(0xFF22141B);
  static const nightRaised = Color(0xFF2E1C25);
  static const nightInk = Color(0xFFF7E8EE);
  static const nightInkSoft = Color(0xFFCDB3BF);
  static const nightPink = Color(0xFFF48FB1);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2185B), Color(0xFFE0457B), Color(0xFFF08A9D)],
  );

  static const softGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFDE7EF), Color(0xFFFFFBF9)],
  );

  static const nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2E1C25), Color(0xFF170D12)],
  );

  /// Distinct, harmonious accents for activity tiles.
  static const activity = <String, Color>{
    'play': Color(0xFFE0457B),
    'watch': Color(0xFF9C4DCC),
    'read': Color(0xFFD9822B),
    'talk': Color(0xFF2E8B9A),
    'date': Color(0xFFC2185B),
    'create': Color(0xFF5C6BC0),
    'surprise': Color(0xFFE8B04B),
  };
}
