/// The action Amazon Bedrock extracts from a screenshot.
///
/// `INTENT` in the wire payload maps 1:1 onto these values. Anything the model
/// is unsure about resolves to [unknown] rather than throwing, because a
/// screenshot we cannot classify should still live in the Vault.
enum SiftIntent {
  payment('PAYMENT', 'Payment'),
  event('EVENT', 'Event'),
  reminder('REMINDER', 'Reminder'),
  link('LINK', 'Link'),
  tracking('TRACKING', 'Tracking'),
  document('DOCUMENT', 'Document'),
  unknown('UNKNOWN', 'Unclassified');

  const SiftIntent(this.wireName, this.label);

  /// Value produced by the Bedrock extractor.
  final String wireName;

  /// Human label rendered on cards and sheets.
  final String label;

  static SiftIntent fromWire(Object? value) {
    if (value is! String) return SiftIntent.unknown;
    final normalized = value.trim().toUpperCase();
    for (final intent in SiftIntent.values) {
      if (intent.wireName == normalized) return intent;
    }
    return SiftIntent.unknown;
  }

  /// True when the intent can be executed natively from the OS.
  bool get isActionable => switch (this) {
        SiftIntent.payment => true,
        SiftIntent.event => true,
        SiftIntent.link => true,
        SiftIntent.reminder => true,
        _ => false,
      };
}
