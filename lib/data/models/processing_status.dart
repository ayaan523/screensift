import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// Lifecycle of a screenshot as it moves through the AWS pipeline.
///
/// The order matches the real journey: capture → presign → S3 upload →
/// Bedrock extraction → DynamoDB write → client poll sees `ready`.
enum ProcessingStatus {
  queued('QUEUED', 'Queued'),
  uploading('UPLOADING', 'Uploading'),
  extracting('EXTRACTING', 'Extracting'),
  ready('READY', 'Ready'),
  failed('FAILED', 'Failed');

  const ProcessingStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get isTerminal =>
      this == ProcessingStatus.ready || this == ProcessingStatus.failed;

  bool get isReady => this == ProcessingStatus.ready;

  /// True while the pipeline still has work to do.
  bool get isInFlight => !isTerminal;

  /// Colour of the badge rendered on a Vault card.
  Color get badgeColor => switch (this) {
        ProcessingStatus.ready => AppPalette.success,
        ProcessingStatus.failed => AppPalette.danger,
        ProcessingStatus.extracting => AppPalette.info,
        ProcessingStatus.uploading => AppPalette.info,
        ProcessingStatus.queued => AppPalette.warning,
      };

  Color get badgeBackground => switch (this) {
        ProcessingStatus.ready => AppPalette.successTint,
        ProcessingStatus.failed => AppPalette.dangerTint,
        ProcessingStatus.extracting => AppPalette.infoTint,
        ProcessingStatus.uploading => AppPalette.infoTint,
        ProcessingStatus.queued => AppPalette.warningTint,
      };

  IconData get badgeIcon => switch (this) {
        ProcessingStatus.ready => Icons.check_circle_rounded,
        ProcessingStatus.failed => Icons.error_rounded,
        ProcessingStatus.extracting => Icons.auto_awesome_rounded,
        ProcessingStatus.uploading => Icons.cloud_upload_rounded,
        ProcessingStatus.queued => Icons.schedule_rounded,
      };

  static ProcessingStatus fromWire(Object? value) {
    if (value is! String) return ProcessingStatus.queued;
    final normalized = value.trim().toUpperCase();
    for (final status in ProcessingStatus.values) {
      if (status.wireName == normalized) return status;
    }
    return ProcessingStatus.queued;
  }
}
