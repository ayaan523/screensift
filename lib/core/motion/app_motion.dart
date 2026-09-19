import 'package:flutter/animation.dart';

/// Motion vocabulary for ScreenSift.
///
/// Every duration and curve in the app comes from here so the whole product
/// moves at one tempo. Three speeds only: quick acknowledgements, standard
/// transitions, and deliberate entrances.
abstract final class AppMotion {
  /// Haptics, chip toggles, icon swaps. Below ~120ms a change reads as a jump
  /// rather than a movement.
  static const Duration quick = Duration(milliseconds: 140);

  /// The default for anything that appears or disappears inline.
  static const Duration standard = Duration(milliseconds: 240);

  /// Card and sheet entrances, where the user is meant to watch.
  static const Duration deliberate = Duration(milliseconds: 420);

  /// Screenshot pipeline progress animations. Slow enough to feel like work is
  /// happening without looking stuck.
  static const Duration loopFast = Duration(milliseconds: 900);
  static const Duration loop = Duration(milliseconds: 1800);

  /// Success and error confirmations.
  static const Duration celebrate = Duration(milliseconds: 1100);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve standardCurve = Curves.easeInOutCubic;

  /// Stagger between siblings in a list entrance.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Cap the stagger so a 40-card grid does not take three seconds to appear.
  static const int maxStaggerIndex = 8;

  /// Delay for the [index]-th child of a staggered entrance.
  static Duration staggerFor(int index) =>
      Duration(milliseconds: stagger.inMilliseconds * index.clamp(0, maxStaggerIndex));
}