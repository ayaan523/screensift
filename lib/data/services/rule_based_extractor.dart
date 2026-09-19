import 'dart:io';

import 'package:intl/intl.dart';

import '../models/sift_capture.dart';
import '../models/sift_category.dart';
import '../models/sift_intent.dart';
import 'capture_extractor.dart';
import 'image_text_reader.dart';

/// Turns screenshot text into a structured action using deterministic rules.
///
/// This is the default extractor: it runs on device, needs no network, and is
/// completely unit-testable because [parse] is pure. OCR is injected so tests
/// can feed text directly.
class RuleBasedExtractor implements CaptureExtractor {
  RuleBasedExtractor({
    ImageTextReader? reader,
    bool Function(String path)? fileExists,
  })  : _reader = reader ?? const NoopTextReader(),
        _fileExists = fileExists ?? _defaultFileExists;

  final ImageTextReader _reader;
  final bool Function(String path) _fileExists;

  static bool _defaultFileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  String get id => 'on_device';

  @override
  String get label => 'On-device rules';

  @override
  bool get requiresNetwork => false;

  @override
  bool get isConfigured => true;

  @override
  Future<SiftExtraction> extract(SiftCapture capture) async {
    final String path = capture.cachedPath ?? '';
    String text = '';
    if (path.isNotEmpty && _fileExists(path)) {
      text = await _reader.read(path);
    }
    return RuleBasedExtractor.parse(
      text,
      name: capture.name,
      now: capture.createdAt,
    );
  }

  // --- pattern tables ------------------------------------------------------

  static final RegExp _amountSymbol = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _amountSuffix = RegExp(
    r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:rupees|rs\b|inr\b)',
    caseSensitive: false,
  );
  static final RegExp _dateNumeric =
      RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');
  static final RegExp _dateDayMonth = RegExp(
    r'\b(\d{1,2})\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)'
    r'[a-z]*\.?\s*(\d{4})?\b',
    caseSensitive: false,
  );
  static final RegExp _dateMonthDay = RegExp(
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)'
    r'[a-z]*\.?\s+(\d{1,2})(?:,?\s*(\d{4}))?\b',
    caseSensitive: false,
  );
  static final RegExp _clock =
      RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);

  static const Map<String, int> _monthIndex = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Keyword votes, in priority order. Earlier intents win ties, which is why
  /// `payment` precedes `reminder` — "pay ₹500 by 5pm" is a payment first.
  static const List<(SiftIntent, List<String>)> _intentRules =
      <(SiftIntent, List<String>)>[
    (
      SiftIntent.payment,
      <String>[
        'upi', 'payment', 'paid', 'debited', 'credited', 'amount',
        'transaction', 'txn', 'transfer', 'refund', 'balance',
      ],
    ),
    (
      SiftIntent.tracking,
      <String>[
        'out for delivery', 'delivered', 'shipment', 'tracking', 'awb',
        'consignment', 'order id', 'order no', 'order #', 'dispatched',
        'pnr', 'order placed',
      ],
    ),
    (
      SiftIntent.event,
      <String>[
        'event', 'meeting', 'webinar', 'conference', 'venue', 'invite',
        'starts at', 'join', 'workshop', 'seminar', 'birthday', 'wedding',
        'function',
      ],
    ),
    (
      SiftIntent.reminder,
      <String>[
        'reminder', 'deadline', 'due date', 'submit', 'submission',
        'assignment', 'last date', 'expires', 'expiry', 'valid till',
        'renewal', 'due on', 'due by',
      ],
    ),
    (
      SiftIntent.link,
      <String>['http://', 'https://', 'www.', 'click here', 'open link'],
    ),
    (
      SiftIntent.document,
      <String>[
        'syllabus', 'module', 'question paper', 'notes', 'chapter',
        'marks', 'result', 'certificate', 'semester',
      ],
    ),
    (SiftIntent.unknown, <String>[]),
  ];

  static const List<(SiftCategory, List<String>)> _categoryRules =
      <(SiftCategory, List<String>)>[
    (
      SiftCategory.finance,
      <String>[
        'upi', '₹', 'rs.', 'amount', 'payment', 'paid', 'bank', 'balance',
        'account', 'debited', 'credited', 'invoice', 'bill', 'refund',
        'transaction', 'txn', 'hdfc', 'icici', 'sbi', 'axis', 'paytm',
        'gpay', 'phonepe', 'netbanking',
      ],
    ),
    (
      SiftCategory.academics,
      <String>[
        'syllabus', 'semester', 'vtu', 'university', 'exam', 'assignment',
        'module', 'lecture', 'subject', 'marks', 'result', 'college',
        'school', 'class', 'notes', 'tutorial',
      ],
    ),
    (
      SiftCategory.travel,
      <String>[
        'flight', 'train', 'pnr', 'boarding', 'irctc', 'hotel', 'booking',
        'trip', 'airport', 'seat', 'departure', 'arrival', 'ola', 'uber',
        'cab', 'boarding pass',
      ],
    ),
    (
      SiftCategory.shopping,
      <String>[
        'flipkart', 'amazon', 'myntra', 'ajio', 'meesho', 'cart', 'shipped',
        'delivery', 'product', 'return', 'swiggy', 'zomato', 'order',
      ],
    ),
    (
      SiftCategory.work,
      <String>[
        'meeting', 'standup', 'sprint', 'jira', 'client', 'project',
        'deploy', 'manager', 'team', 'office', 'hr', 'performance review',
      ],
    ),
    (SiftCategory.personal, <String>[]),
  ];

  // --- engine --------------------------------------------------------------

  /// The whole rule engine, as a pure function.
  ///
  /// Kept static and side-effect free so the parsing behaviour can be tested
  /// exhaustively without a device, an image, or OCR.
  static SiftExtraction parse(String rawText, {String name = '', DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    // Non-breaking spaces appear in OCR output from currency formatting.
    final String text = rawText.replaceAll('\u00A0', ' ').trim();
    final String haystack = text.toLowerCase();

    // The filename is weak evidence, so it only ever adds a vote; it can never
    // out-score something the OCR actually read.
    final String nameHaystack =
        name.toLowerCase().replaceAll(RegExp(r'[_\-.]'), ' ');

    final String? amountText = _findFirstGroup(text, <RegExp>[
      _amountSymbol,
      _amountSuffix,
    ]);
    final double? amount = amountText == null ? null : _toAmount(amountText);
    final String? upi = _findUpi(text);
    final String? link = _findLink(text);
    final String? referenceCode = _findReference(text);
    final DateTime? dueAt = _findDateTime(text, reference);

    final (SiftIntent intent, int intentScore) = _scoreIntent(
      haystack,
      nameHaystack,
      amount: amount,
      upiId: upi,
      link: link,
      reference: referenceCode,
    );
    final (SiftCategory category, int categoryScore) = _scoreCategory(
      intent: intent,
      text: haystack,
      name: nameHaystack,
      amount: amount,
    );

    final String currency = _detectCurrency(text);
    final String? payeeName = _derivePayee(text, upi);
    final String? title = _deriveTitle(
      text: text,
      intent: intent,
      amount: amount,
      currency: currency,
      payeeName: payeeName,
      reference: referenceCode,
      link: link,
    );
    final String? summary = _deriveSummary(
      intent: intent,
      category: category,
      amountLabel: amount == null ? null : _formatAmount(amount, currency),
      payeeName: payeeName,
      dueAt: dueAt,
      reference: referenceCode,
      link: link,
    );

    final List<String> tags = <String>[
      category.shortLabel,
      intent.label,
      ?referenceCode,
    ];

    final int evidence = intentScore + categoryScore;
    final double confidence =
        (evidence / (evidence + 4)).clamp(0.0, 1.0).toDouble();

    return SiftExtraction(
      intent: intent,
      category: category,
      title: title,
      summary: summary,
      amount: amount,
      currency: currency,
      upiId: upi,
      payeeName: payeeName,
      link: link,
      dueAt: dueAt,
      referenceCode: referenceCode,
      tags: tags,
      confidence: confidence,
    );
  }
}

// --- extraction helpers ----------------------------------------------------
// Top level, but still library-private, so they can read the pattern tables
// above without exposing them to the rest of the app.

String? _findFirstGroup(String text, List<RegExp> patterns) {
  for (final RegExp pattern in patterns) {
    final RegExpMatch? match = pattern.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      final String? value = match.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

double? _toAmount(String raw) {
  final String cleaned = raw.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
  final double? value = double.tryParse(cleaned);
  if (value == null || value <= 0 || value > 100000000) return null;
  return value;
}

String _detectCurrency(String text) {
  if (text.contains('₹') || RegExp(r'\b(?:rs\.?|inr|rupees)\b', caseSensitive: false).hasMatch(text)) {
    return 'INR';
  }
  if (text.contains(r'$')) return 'USD';
  if (text.contains('€')) return 'EUR';
  if (text.contains('£')) return 'GBP';
  return 'INR';
}

String _formatAmount(double value, String currency) {
  final bool isWhole = value == value.roundToDouble();
  final String digits = isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  final String symbol = switch (currency) {
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    _ => '₹',
  };
  return '$symbol$digits';
}

/// A VPA is only plausible when the domain looks like a real payment handle —
/// otherwise `something@company.com` would be reported as a UPI id.
String? _findUpi(String text) {
  const Set<String> knownHandles = <String>{
    'okhdfcbank', 'okicici', 'okaxis', 'oksbi', 'okhsbc', 'ybl', 'ibl', 'axl',
    'apl', 'paytm', 'upi', 'airtel', 'jio', 'fbl', 'freecharge', 'axisb',
    'hdfcbank', 'icici', 'sbi', 'kotak', 'barodampay', 'pnb',
  };
  for (final RegExpMatch match in _upiIdPattern.allMatches(text)) {
    final String local = match.group(1) ?? '';
    final String domain = (match.group(2) ?? '').toLowerCase();
    if (local.length < 2) continue;
    // Skip anything that is obviously an email address.
    if (domain.contains('.') && !knownHandles.contains(domain)) continue;
    if (knownHandles.contains(domain)) return '$local@$domain';
  }
  // Fall back to the first plausible handle even if the domain is unfamiliar,
  // but only when the text also talks about paying.
  if (RegExp(r'\bupi\b|\bpay\b|\bvpa\b', caseSensitive: false).hasMatch(text)) {
    for (final RegExpMatch match in _upiIdPattern.allMatches(text)) {
      final String domain = (match.group(2) ?? '').toLowerCase();
      if (domain.length <= 12 && !domain.contains('.')) {
        return '${match.group(1)}@$domain';
      }
    }
  }
  return null;
}

final RegExp _upiIdPattern = RegExp(
  r'\b([a-zA-Z0-9][a-zA-Z0-9._-]{1,64})@([a-zA-Z][a-zA-Z0-9.]{1,24})\b',
);

String? _findLink(String text) {
  final RegExpMatch? withScheme = _urlPattern.firstMatch(text);
  if (withScheme != null) {
    return withScheme.group(0)!.replaceAll(RegExp(r'[.,;)\]]+$'), '');
  }
  final RegExpMatch? bare = _bareDomainPattern.firstMatch(text);
  if (bare == null) return null;
  final String value = bare.group(0)!.replaceAll(RegExp(r'[.,;)\]]+$'), '');
  return value.startsWith('www.') ? 'https://$value' : 'https://$value';
}

final RegExp _urlPattern = RegExp(r'https?://[^\s<>")\]]+', caseSensitive: false);
final RegExp _bareDomainPattern = RegExp(
  r'\b(?:www\.[^\s]+|[a-z0-9][a-z0-9-]*\.'
  r'(?:com|in|org|net|io|co|me|app|dev|gov|edu)(?:/[^\s]*)?)\b',
  caseSensitive: false,
);

String? _findReference(String text) {
  final RegExpMatch? match = _referencePattern.firstMatch(text);
  final String? value = match?.group(1);
  if (value == null) return null;
  return value.replaceAll(RegExp(r'-+$'), '');
}

final RegExp _referencePattern = RegExp(
  r'\b(?:awb|tracking(?:\s*(?:id|no|number))?|shipment|consignment|'
  r'order(?:\s*(?:id|no|number|#))?|ticket(?:\s*(?:id|no))?|'
  r'pnr|booking(?:\s*(?:id|no))?|ref(?:erence)?(?:\s*(?:id|no))?)\b'
  r'[^A-Za-z0-9]{0,8}([A-Z0-9][A-Z0-9-]{4,24})',
  caseSensitive: false,
);

/// Relative words first (they are unambiguous), then absolute date formats.
DateTime? _findDateTime(String text, DateTime now) {
  final String lower = text.toLowerCase();
  final (int? hour, int? minute) = _findClock(text);

  DateTime? day;
  if (RegExp(r'\btomorrow\b').hasMatch(lower)) {
    day = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  } else if (RegExp(r'\btoday\b').hasMatch(lower)) {
    day = DateTime(now.year, now.month, now.day);
  } else {
    day = _findCalendarDate(text, now);
  }

  if (day == null && hour == null) return null;
  final DateTime base = day ?? DateTime(now.year, now.month, now.day);
  if (hour == null) return base;
  return DateTime(base.year, base.month, base.day, hour, minute ?? 0);
}

(int?, int?) _findClock(String text) {
  final RegExpMatch? match = RuleBasedExtractor._clock.firstMatch(text);
  if (match == null) return (null, null);
  int hour = int.parse(match.group(1)!);
  final int minute =
      match.group(2) == null ? 0 : int.parse(match.group(2)!);
  final String meridiem = match.group(3)!.toLowerCase();
  if (meridiem == 'pm' && hour < 12) hour += 12;
  if (meridiem == 'am' && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return (null, null);
  return (hour, minute);
}

DateTime? _findCalendarDate(String text, DateTime now) {
  final RegExpMatch? numeric = RuleBasedExtractor._dateNumeric.firstMatch(text);
  if (numeric != null) {
    int first = int.parse(numeric.group(1)!);
    int second = int.parse(numeric.group(2)!);
    int year = int.parse(numeric.group(3)!);
    if (year < 100) year += 2000;
    // Day-first is the convention on Indian documents, but swap when the
    // second component cannot be a month.
    int day = first;
    int month = second;
    if (month > 12 && day <= 12) {
      day = second;
      month = first;
    }
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day);
    }
  }

  final RegExpMatch? dayMonth =
      RuleBasedExtractor._dateDayMonth.firstMatch(text);
  final int? dmMonth = _monthOf(dayMonth?.group(2));
  if (dayMonth != null && dmMonth != null) {
    final int day = int.parse(dayMonth.group(1)!);
    final int year =
        dayMonth.group(3) == null ? now.year : int.parse(dayMonth.group(3)!);
    if (day >= 1 && day <= 31) return DateTime(year, dmMonth, day);
  }

  final RegExpMatch? monthDay =
      RuleBasedExtractor._dateMonthDay.firstMatch(text);
  final int? mdMonth = _monthOf(monthDay?.group(1));
  if (monthDay != null && mdMonth != null) {
    final int day = int.parse(monthDay.group(2)!);
    final int year =
        monthDay.group(3) == null ? now.year : int.parse(monthDay.group(3)!);
    if (day >= 1 && day <= 31) return DateTime(year, mdMonth, day);
  }

  return null;
}

int? _monthOf(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final String key = raw.toLowerCase();
  return RuleBasedExtractor._monthIndex[key.substring(0, 3)];
}

// --- scoring ---------------------------------------------------------------

(SiftIntent, int) _scoreIntent(
  String text,
  String name, {
  required double? amount,
  required String? upiId,
  required String? link,
  required String? reference,
}) {
  SiftIntent best = SiftIntent.unknown;
  int bestScore = 0;

  for (final (SiftIntent intent, List<String> keywords)
      in RuleBasedExtractor._intentRules) {
    int score = 0;
    for (final String keyword in keywords) {
      if (text.contains(keyword)) {
        score += 2;
      } else if (name.contains(keyword)) {
        score += 1;
      }
    }

    // Structural evidence outranks vocabulary: a real VPA or amount is a far
    // stronger signal than the word "payment" appearing somewhere.
    if (intent == SiftIntent.payment) {
      if (upiId != null) score += 5;
      if (amount != null) score += 3;
    }
    if (intent == SiftIntent.tracking && reference != null) score += 3;
    if (intent == SiftIntent.link && link != null) score += 5;

    if (score > bestScore) {
      bestScore = score;
      best = intent;
    }
  }
  return (best, bestScore);
}

(SiftCategory, int) _scoreCategory({
  required SiftIntent intent,
  required String text,
  required String name,
  required double? amount,
}) {
  SiftCategory best = SiftCategory.personal;
  int bestScore = 0;

  for (final (SiftCategory category, List<String> keywords)
      in RuleBasedExtractor._categoryRules) {
    int score = 0;
    for (final String keyword in keywords) {
      if (text.contains(keyword)) {
        score += 2;
      } else if (name.contains(keyword)) {
        score += 1;
      }
    }

    if (intent == SiftIntent.payment && category == SiftCategory.finance) {
      score += 4;
    }
    if (amount != null && category == SiftCategory.finance) score += 2;
    if ((intent == SiftIntent.document || intent == SiftIntent.reminder) &&
        category == SiftCategory.academics) {
      score += 2;
    }
    if (intent == SiftIntent.tracking &&
        (category == SiftCategory.shopping ||
            category == SiftCategory.travel)) {
      score += 2;
    }

    if (score > bestScore) {
      bestScore = score;
      best = category;
    }
  }
  return (best, bestScore);
}

// --- presentation derivation ----------------------------------------------

/// Who the payment is going to.
///
/// Prefers an explicit "pay to X" phrase; falls back to humanising the local
/// part of the VPA, which is usually the person's name.
String? _derivePayee(String text, String? upiId) {
  final RegExpMatch? explicit = _payeePattern.firstMatch(text);
  if (explicit != null) {
    final String candidate =
        explicit.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.length >= 2 && candidate.length <= 40) {
      return _titleCase(candidate);
    }
  }

  final String? vpa = upiId;
  if (vpa == null) return null;
  final String local = vpa
      .split('@')
      .first
      .replaceAll(RegExp(r'[0-9]+'), '')
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .trim();
  if (local.length < 2) return null;
  return _titleCase(local);
}

final RegExp _payeePattern = RegExp(
  r'\b(?:pay\s+to|paid\s+to|payment\s+to|transfer\s+to|to)\s+'
  r'([A-Za-z][A-Za-z .&]{1,40})',
);

String? _deriveTitle({
  required String text,
  required SiftIntent intent,
  required double? amount,
  required String currency,
  required String? payeeName,
  required String? reference,
  required String? link,
}) {
  final String? amountLabel =
      amount == null ? null : _formatAmount(amount, currency);
  final String? payee = payeeName;
  final String? ref = reference;
  final String? url = link;

  if (intent == SiftIntent.payment) {
    if (amountLabel != null && payee != null) {
      return 'Pay $amountLabel to $payee';
    }
    if (amountLabel != null) return 'Payment of $amountLabel';
    if (payee != null) return 'Payment to $payee';
  }
  if (intent == SiftIntent.tracking && ref != null) {
    return 'Track order $ref';
  }
  if (intent == SiftIntent.link && url != null) {
    return _shortHost(url);
  }
  return _firstMeaningfulLine(text);
}

String? _deriveSummary({
  required SiftIntent intent,
  required SiftCategory category,
  required String? amountLabel,
  required String? payeeName,
  required DateTime? dueAt,
  required String? reference,
  required String? link,
}) {
  final List<String> parts = <String>[];
  final String? when = dueAt == null ? null : DateFormat('d MMM, h:mm a').format(dueAt);

  if (intent == SiftIntent.payment) {
    parts.add(amountLabel == null ? 'Payment request' : 'Payment of $amountLabel');
    if (payeeName != null) parts.add('to $payeeName');
    if (when != null) parts.add('due $when');
  } else if (intent == SiftIntent.tracking) {
    parts.add('Shipment update');
    if (reference != null) parts.add('ref $reference');
  } else if (intent == SiftIntent.event) {
    parts.add('Event captured');
    if (when != null) parts.add('on $when');
  } else if (intent == SiftIntent.reminder) {
    parts.add('Reminder');
    if (when != null) parts.add('due $when');
  } else if (intent == SiftIntent.link) {
    parts.add('Saved link');
    if (link != null) parts.add(_shortHost(link));
  } else if (intent == SiftIntent.document) {
    parts.add('Filed under ${category.label}');
  } else {
    return null;
  }
  return parts.join(' · ');
}

/// The first line that reads like a heading rather than a number or timestamp.
String? _firstMeaningfulLine(String text) {
  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    if (line.length < 4) continue;
    final int digits = line.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits > line.length * 0.6) continue;
    if (RegExp(r'^\d{1,2}:\d{2}(?:\s*[ap]m)?$', caseSensitive: false)
        .hasMatch(line)) {
      continue;
    }
    return line.length > 70 ? '${line.substring(0, 67)}…' : line;
  }
  return null;
}

String _shortHost(String url) {
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return url;
  return parsed.host.replaceFirst('www.', '');
}

String _titleCase(String value) {
  return value
      .split(' ')
      .where((String part) => part.isNotEmpty)
      .map((String part) =>
          part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}