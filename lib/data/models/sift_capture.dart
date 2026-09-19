import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'processing_status.dart';
import 'sift_category.dart';
import 'sift_intent.dart';

/// One screenshot and everything ScreenSift has learned about it.
///
/// This is the object the whole app is built around: the native layer produces
/// the identity fields (`id`, `createdAt`, `cachedPath`), the extractor fills in
/// the semantic fields (`intent`, `amount`, `upiId`, …), and the UI renders it.
/// Immutable, with [copyWith] used to move a capture through the pipeline.
@immutable
class SiftCapture {
  const SiftCapture({
    required this.id,
    required this.createdAt,
    required this.name,
    this.status = ProcessingStatus.queued,
    this.category = SiftCategory.personal,
    this.intent = SiftIntent.unknown,
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
    this.cachedPath,
    this.sourcePath,
    this.sizeBytes = 0,
    this.confidence = 0,
    this.errorMessage,
    this.archived = false,
  });

  /// `MediaStore.Images._ID`. Stable and unique, so it doubles as our key for
  /// deduplication and persistence.
  final int id;

  final DateTime createdAt;

  /// Original file name, kept for diagnostics and as a display fallback.
  final String name;

  final ProcessingStatus status;
  final SiftCategory category;
  final SiftIntent intent;

  /// Extracted headline, e.g. "VTU Syllabus: Module 1".
  final String? title;

  /// One-line explanation of what the capture is.
  final String? summary;

  /// Payment amount, in [currency]'s major unit.
  final double? amount;
  final String currency;

  final String? upiId;
  final String? payeeName;
  final String? link;

  /// When an event happens or a payment is due.
  final DateTime? dueAt;

  /// Tracking number, order id, or ticket reference.
  final String? referenceCode;

  final List<String> tags;

  /// App-private copy of the image, written by the native layer.
  final String? cachedPath;

  /// Original path, when the platform still exposes one.
  final String? sourcePath;

  final int sizeBytes;

  /// Extractor confidence, `0..1`.
  final double confidence;

  final String? errorMessage;

  /// User filed this away; it leaves the main Vault but is never deleted.
  final bool archived;

  // --- derived -------------------------------------------------------------

  bool get isReady => status.isReady;

  bool get isInFlight => status.isInFlight;

  bool get isFailed => status == ProcessingStatus.failed;

  /// True when ScreenSift can actually do something with this on tap.
  bool get isActionable => intent.isActionable && !isFailed;

  /// What the card shows as its heading.
  String get displayTitle {
    final String? candidate = title?.trim();
    if (candidate != null && candidate.isNotEmpty) return candidate;
    return _prettifiedName;
  }

  /// Clock time, e.g. `1:13 AM`.
  String get timeLabel => DateFormat.jm().format(createdAt);

  /// `Today · 1:13 AM`, `Yesterday · …`, or `12 Sep · …`.
  String get relativeLabel {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final int deltaDays = today.difference(day).inDays;

    if (deltaDays == 0) return 'Today · $timeLabel';
    if (deltaDays == 1) return 'Yesterday · $timeLabel';
    return '${DateFormat.MMMd().format(createdAt)} · $timeLabel';
  }

  /// `₹450` / `$12.50` / null when there is no amount.
  String? get amountLabel {
    final double? value = amount;
    if (value == null) return null;
    final String symbol = switch (currency.toUpperCase()) {
      'INR' => '₹',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    final bool isWhole = value == value.roundToDouble();
    final String digits =
        isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    // Indian grouping for rupees reads more naturally than western grouping.
    final String grouped =
        currency.toUpperCase() == 'INR' ? _groupIndian(digits) : digits;
    return '$symbol$grouped';
  }

  String get _prettifiedName {
    final String base = name.replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '');
    final String spaced = base.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
    if (spaced.isEmpty) return 'Screenshot';
    return spaced
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .map((String part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  // --- serialisation -------------------------------------------------------

  /// Builds a capture from the map produced by `MediaStoreImage.toMap`.
  ///
  /// Defensive on purpose: the bridge is a process boundary, so a missing or
  /// mistyped key must degrade rather than throw inside a stream listener.
  factory SiftCapture.fromNativeMap(Map<Object?, Object?> raw) {
    final Object? rawId = raw['id'];
    final Object? rawAdded = raw['date_added'];
    return SiftCapture(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      createdAt: rawAdded is num
          ? DateTime.fromMillisecondsSinceEpoch(rawAdded.toInt())
          : DateTime.now(),
      name: '${raw['name'] ?? 'screenshot'}',
      cachedPath: raw['cached_path'] as String?,
      sourcePath: raw['source_path'] as String?,
      sizeBytes: raw['size'] is num ? (raw['size']! as num).toInt() : 0,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'name': name,
        'status': status.wireName,
        'category': category.wireName,
        'intent': intent.wireName,
        'title': title,
        'summary': summary,
        'amount': amount,
        'currency': currency,
        'upi_id': upiId,
        'payee_name': payeeName,
        'link': link,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'reference_code': referenceCode,
        'tags': tags,
        'cached_path': cachedPath,
        'source_path': sourcePath,
        'size_bytes': sizeBytes,
        'confidence': confidence,
        'error_message': errorMessage,
        'archived': archived,
      };

  factory SiftCapture.fromJson(Map<String, Object?> json) {
    return SiftCapture(
      id: (json['id'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as num?)?.toInt() ?? 0,
      ),
      name: '${json['name'] ?? 'screenshot'}',
      status: ProcessingStatus.fromWire(json['status']),
      category: SiftCategory.fromWire(json['category']),
      intent: SiftIntent.fromWire(json['intent']),
      title: json['title'] as String?,
      summary: json['summary'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: '${json['currency'] ?? 'INR'}',
      upiId: json['upi_id'] as String?,
      payeeName: json['payee_name'] as String?,
      link: json['link'] as String?,
      dueAt: json['due_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch((json['due_at']! as num).toInt())
          : null,
      referenceCode: json['reference_code'] as String?,
      tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? tag) => '$tag')
          .toList(growable: false),
      cachedPath: json['cached_path'] as String?,
      sourcePath: json['source_path'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      errorMessage: json['error_message'] as String?,
      archived: json['archived'] == true,
    );
  }

  SiftCapture copyWith({
    ProcessingStatus? status,
    SiftCategory? category,
    SiftIntent? intent,
    String? title,
    String? summary,
    double? amount,
    String? currency,
    String? upiId,
    String? payeeName,
    String? link,
    DateTime? dueAt,
    String? referenceCode,
    List<String>? tags,
    String? cachedPath,
    double? confidence,
    String? errorMessage,
    bool? archived,
    bool clearError = false,
  }) {
    return SiftCapture(
      id: id,
      createdAt: createdAt,
      name: name,
      status: status ?? this.status,
      category: category ?? this.category,
      intent: intent ?? this.intent,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      upiId: upiId ?? this.upiId,
      payeeName: payeeName ?? this.payeeName,
      link: link ?? this.link,
      dueAt: dueAt ?? this.dueAt,
      referenceCode: referenceCode ?? this.referenceCode,
      tags: tags ?? this.tags,
      cachedPath: cachedPath ?? this.cachedPath,
      sourcePath: sourcePath,
      sizeBytes: sizeBytes,
      confidence: confidence ?? this.confidence,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      archived: archived ?? this.archived,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SiftCapture &&
      other.id == id &&
      other.status == status &&
      other.intent == intent &&
      other.category == category &&
      other.title == title &&
      other.amount == amount &&
      other.archived == archived;

  @override
  int get hashCode =>
      Object.hash(id, status, intent, category, title, amount, archived);

  @override
  String toString() =>
      'SiftCapture(#$id, ${status.wireName}, ${intent.wireName}, $name)';
}

/// Indian digit grouping: `1234567` -> `12,34,567`.
String _groupIndian(String digits) {
  final int dot = digits.indexOf('.');
  final String whole = dot == -1 ? digits : digits.substring(0, dot);
  final String fraction = dot == -1 ? '' : digits.substring(dot);
  if (whole.length <= 3) return '$whole$fraction';

  final String head = whole.substring(0, whole.length - 3);
  final String tail = whole.substring(whole.length - 3);
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i) % 2 == 0) grouped.write(',');
    grouped.write(head[i]);
  }
  return '$grouped,$tail$fraction';
}
