/// Life-area buckets used by the Vault filter chips and the Action Hub.
///
/// Categories are assigned by the Bedrock extractor. They are intentionally
/// coarse — six buckets a user can recognise instantly beat a taxonomy nobody
/// bothers to filter by.
enum SiftCategory {
  all('ALL', 'All', 'Inbox'),
  academics('ACADEMICS', 'Academics', 'School'),
  finance('FINANCE', 'Finance', 'Money'),
  work('WORK', 'Work', 'Work'),
  travel('TRAVEL', 'Travel', 'Travel'),
  shopping('SHOPPING', 'Shopping', 'Shopping'),
  personal('PERSONAL', 'Personal', 'Life');

  const SiftCategory(this.wireName, this.label, this.shortLabel);

  final String wireName;
  final String label;

  /// Compact label for dense chips and card tags.
  final String shortLabel;

  /// [all] is a view filter, never a stored value.
  bool get isFilterable => this != SiftCategory.all;

  static SiftCategory fromWire(Object? value) {
    if (value is! String) return SiftCategory.personal;
    final normalized = value.trim().toUpperCase();
    for (final category in SiftCategory.values) {
      if (category.wireName == normalized) return category;
    }
    return SiftCategory.personal;
  }
}
