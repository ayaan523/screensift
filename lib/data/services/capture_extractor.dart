import 'package:flutter/foundation.dart';

import '../models/processing_status.dart';
import '../models/sift_capture.dart';
import '../models/sift_category.dart';
import '../models/sift_intent.dart';

/// What an extractor understood from a screenshot.
///
/// A deliberately flat value object: both the on-device rule engine and the
/// remote model return exactly this, so the repository never has to care which
/// one ran.
@immutable
class SiftExtraction {
  const SiftExtraction({
    required this.intent,
    required this.category,
    this.title,
    this.summary,
    this.amount,
    this.currency = 'INR',
    this.upiId,
    this.payeeName,
    this.link,
    this.dueAt,
    this.referenceCode,
    this.tags = const <String>[],
    this.confidence = 0,
  });

  /// Nothing usable was found. The capture is still kept.
  static const SiftExtraction unknown = SiftExtraction(
    intent: SiftIntent.unknown,
    category: SiftCategory.personal,
  );

  final SiftIntent intent;
  final SiftCategory category;
  final String? title;
  final String? summary;
  final double? amount;
  final String currency;
  final String? upiId;
  final String? payeeName;
  final String? link;
  final DateTime? dueAt;
  final String? referenceCode;
  final List<String> tags;

  /// `0..1`. Exposed in the UI so a shaky guess looks shaky.
  final double confidence;

  /// Applies this extraction to [capture], marking it ready.
  SiftCapture applyTo(SiftCapture capture) {
    return capture.copyWith(
      status: ProcessingStatus.ready,
      intent: intent,
      category: category,
      title: title,
      summary: summary,
      amount: amount,
      currency: currency,
      upiId: upiId,
      payeeName: payeeName,
      link: link,
      dueAt: dueAt,
      referenceCode: referenceCode,
      tags: tags,
      confidence: confidence,
      clearError: true,
    );
  }
}

/// A single abstraction the pipeline talks to.
///
/// Swapping the on-device rule engine for the cloud model is a constructor
/// argument, never a code change in the UI.
abstract interface class CaptureExtractor {
  /// Stable identifier used in settings and logs.
  String get id;

  /// Human label shown in Settings.
  String get label;

  /// True when this extractor needs a network round trip.
  bool get requiresNetwork;

  /// True when this extractor is configured well enough to run.
  bool get isConfigured;

  Future<SiftExtraction> extract(SiftCapture capture);
}
