import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_palette.dart';

/// Every animation the app ships, in one place.
///
/// They live in `assets/lottie/` and are bundled rather than fetched, so the UI
/// can never flash or break because a CDN is unreachable.
abstract final class AppLottie {
  static const String vaultEmpty = 'assets/lottie/vault_empty.json';
  static const String scanning = 'assets/lottie/scanning.json';
  static const String success = 'assets/lottie/success.json';
  static const String error = 'assets/lottie/error.json';
  static const String bell = 'assets/lottie/bell.json';
  static const String searchEmpty = 'assets/lottie/search_empty.json';

  static const List<String> all = <String>[
    vaultEmpty,
    scanning,
    success,
    error,
    bell,
    searchEmpty,
  ];
}

/// A Lottie animation that can never take a screen down with it.
///
/// Two production concerns are handled here rather than at every call site:
///  * if the asset fails to decode we fall back to a plain icon;
///  * if the platform asks for reduced motion we render a still frame instead
///    of looping, which is what `MediaQuery.disableAnimations` is for.
class SiftLottie extends StatelessWidget {
  const SiftLottie(
    this.asset, {
    super.key,
    this.size = 140,
    this.controller,
    this.repeat = true,
    this.fit = BoxFit.contain,
    this.fallbackIcon = Icons.auto_awesome_rounded,
    this.semanticLabel,
  });

  /// One of the [AppLottie] constants.
  final String asset;

  final double size;
  final Animation<double>? controller;
  final bool repeat;
  final BoxFit fit;
  final IconData fallbackIcon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    final Widget animation = Lottie.asset(
      asset,
      controller: controller,
      // Honouring the accessibility setting matters more than the flourish.
      animate: !reduceMotion,
      repeat: repeat && !reduceMotion,
      fit: fit,
      width: size,
      height: size,
      addRepaintBoundary: true,
      // Assets ship inside the bundle, so reaching here means the bundle is
      // broken. Degrade to an icon instead of throwing mid-frame.
      errorBuilder: (context, error, stackTrace) => _FallbackIcon(
        icon: fallbackIcon,
        size: size,
      ),
    );

    final String? label = semanticLabel;
    if (label == null) return animation;
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(child: animation),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          icon,
          size: size * 0.5,
          color: AppPalette.slateFaint,
        ),
      ),
    );
  }
}
