import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'sift_lottie.dart';

/// The three non-content states every data screen needs.
///
/// They share one skeleton so an empty Vault, a failed scan and a cold start
/// all look like the same product instead of three different apps.
class SiftEmptyState extends StatelessWidget {
  const SiftEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.asset = AppLottie.vaultEmpty,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String asset;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      asset: asset,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class SiftErrorState extends StatelessWidget {
  const SiftErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.actionLabel = 'Try again',
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      asset: AppLottie.error,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      tone: AppPalette.danger,
    );
  }
}

class SiftLoadingState extends StatelessWidget {
  const SiftLoadingState({
    super.key,
    this.title = 'Reading your screenshots',
    this.message = 'Pulling out payments, events and links.',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      asset: AppLottie.scanning,
      title: title,
      message: message,
    );
  }
}

class _StateScaffold extends StatelessWidget {
  const _StateScaffold({
    required this.asset,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AppPalette.tealDeep,
  });

  final String asset;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? label = actionLabel;
    final VoidCallback? action = onAction;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gutter + 8,
          vertical: AppTheme.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SiftLottie(
              asset,
              size: 150,
              semanticLabel: title,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: tone),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ),
            if (label != null && action != null) ...<Widget>[
              const SizedBox(height: 22),
              FilledButton(
                onPressed: action,
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A skeleton block used while real content is still loading.
class SiftShimmerBox extends StatefulWidget {
  const SiftShimmerBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppTheme.radiusSm,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<SiftShimmerBox> createState() => _SiftShimmerBoxState();
}

class _SiftShimmerBoxState extends State<SiftShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.loop,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + t * 3, 0),
              end: Alignment(-0.5 + t * 3, 0),
              colors: const <Color>[
                AppPalette.canvasAlt,
                AppPalette.border,
                AppPalette.canvasAlt,
              ],
            ),
          ),
        );
      },
    );
  }
}
