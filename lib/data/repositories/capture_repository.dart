import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/native_screenshot_source.dart';
import '../datasources/settings_store.dart';
import '../models/processing_status.dart';
import '../models/sift_capture.dart';
import '../models/sift_category.dart';
import '../services/capture_extractor.dart';

class CaptureRepository extends ChangeNotifier {
  CaptureRepository({
    required this.native,
    required this.settings,
    required this.prefs,
    required this.buildExtractor,
    this.onCaptureReady,
  });

  final NativeScreenshotSource native;
  final SettingsStore settings;
  final SharedPreferences prefs;
  final CaptureExtractor Function() buildExtractor;
  final ValueChanged<SiftCapture>? onCaptureReady;

  static const String _capturesKey = 'captures_v1';
  static const int _maxCaptures = 300;

  final List<SiftCapture> _captures = [];
  StreamSubscription<Map<Object?, Object?>>? _subscription;

  bool _initialized = false;
  bool _isProcessing = false;
  bool _mounted = true; // Added to fix the 'mounted' check errors
  SiftCapture? _active;
  SiftCapture? _lastReady;
  String? _lastError;
  PlatformSnapshot _platform = const PlatformSnapshot();

  SiftCategory _category = SiftCategory.all;
  String _query = '';
  bool _showArchived = false;
  bool _onlyActionable = false;

  bool get initialized => _initialized;
  bool get isProcessing => _isProcessing;
  SiftCapture? get active => _active;
  SiftCapture? get lastReady => _lastReady;
  String? get lastError => _lastError;
  PlatformSnapshot get platform => _platform;
  SiftCategory get category => _category;
  String get query => _query;
  bool get showArchived => _showArchived;
  bool get onlyActionable => _onlyActionable;

  List<SiftCapture> get all => List.unmodifiable(_captures);

  int get inFlightCount => _captures.where((c) => c.isInFlight).length;
  int get actionableCount =>
      _captures.where((c) => c.isActionable && !c.archived).length;
  int get archivedCount => _captures.where((c) => c.archived).length;
  int get failedCount => _captures.where((c) => c.isFailed).length;

  List<SiftCapture> get visible {
    final needle = _query.trim().toLowerCase();
    return _captures.where((c) {
      if (c.archived != _showArchived) return false;
      if (_category != SiftCategory.all && c.category != _category) {
        return false;
      }
      if (_onlyActionable && !c.isActionable) return false;
      if (needle.isEmpty) return true;
      return c.displayTitle.toLowerCase().contains(needle) ||
          c.name.toLowerCase().contains(needle) ||
          (c.summary?.toLowerCase().contains(needle) ?? false) ||
          (c.upiId?.toLowerCase().contains(needle) ?? false) ||
          (c.referenceCode?.toLowerCase().contains(needle) ?? false) ||
          (c.link?.toLowerCase().contains(needle) ?? false) ||
          c.intent.label.toLowerCase().contains(needle) ||
          c.category.label.toLowerCase().contains(needle) ||
          c.tags.any((t) => t.toLowerCase().contains(needle));
    }).toList();
  }

  Map<SiftCategory, int> get categoryCounts {
    final counts = <SiftCategory, int>{
      for (final v in SiftCategory.values) v: 0,
    };
    for (final c in _captures) {
      if (c.archived != _showArchived) continue;
      if (_onlyActionable && !c.isActionable) continue;
      counts[c.category] = (counts[c.category] ?? 0) + 1;
      counts[SiftCategory.all] = (counts[SiftCategory.all] ?? 0) + 1;
    }
    return counts;
  }

  SiftCapture? byId(int id) {
    for (final c in _captures) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadCaptures();
    _startWatching();
    await _refreshPlatform();
    // Keep the native watcher in step with the persisted toggle. A cold start
    // with watching off must not leave the foreground service running.
    if (settings.watchEnabled) {
      await native.startWatching();
    } else {
      await native.stopWatching();
    }
    // Captures the watcher saw while Dart was down are queued natively and
    // drained here so nothing is lost across restarts.
    final buffered = await native.drainBufferedCaptures();
    for (final raw in buffered) {
      _onCaptureEvent(raw);
    }
    // Import screenshots already on the device on first run. Media
    // permission must be granted first or the query comes back empty.
    if (_captures.isEmpty) {
      await _ensurePermissions();
      await importRecent();
    }
    notifyListeners();
  }

  /// Asks for media access once per install. Silent when already granted so
  /// cold starts never flash a dialog.
  Future<void> _ensurePermissions() async {
    final bool granted = await native.hasPermission(
      NativeScreenshotSource.permissionMedia,
    );
    if (!granted) {
      await native.requestPermission(NativeScreenshotSource.permissionMedia);
    }
  }

  @override
  void dispose() {
    _mounted = false; // Mark as unmounted before disposing
    _subscription?.cancel();
    _subscription = null;
    _active = null;
    super.dispose(); // Use the standard ChangeNotifier dispose
  }

  void setCategory(SiftCategory value) {
    if (_category == value) return;
    _category = value;
    notifyListeners();
  }

  void setQuery(String value) {
    final trimmed = value.trim();
    if (_query == trimmed) return;
    _query = trimmed;
    notifyListeners();
  }

  void toggleShowArchived() {
    _showArchived = !_showArchived;
    notifyListeners();
  }

  void toggleOnlyActionable() {
    _onlyActionable = !_onlyActionable;
    notifyListeners();
  }

  void setArchivedFilter(bool show) {
    _showArchived = show;
    notifyListeners();
  }

  void setOnlyActionable(bool only) {
    _onlyActionable = only;
    notifyListeners();
  }

  void archive(SiftCapture capture) {
    final idx = _captures.indexWhere((c) => c.id == capture.id);
    if (idx == -1) return;
    _captures[idx] = _captures[idx].copyWith(archived: true);
    _persist();
    notifyListeners();
  }

  void unarchive(SiftCapture capture) {
    final idx = _captures.indexWhere((c) => c.id == capture.id);
    if (idx == -1) return;
    _captures[idx] = _captures[idx].copyWith(archived: false);
    _persist();
    notifyListeners();
  }

  Future<bool> delete(SiftCapture capture) async {
    final deleted = await native.requestDeleteCapture(capture.id);
    if (deleted) {
      _captures.removeWhere((c) => c.id == capture.id);
      _persist();
      notifyListeners();
    }
    return deleted;
  }

  int prune(DateTime olderThan) {
    final kept = <SiftCapture>[];
    var removed = 0;
    for (final c in _captures) {
      if (c.createdAt.isBefore(olderThan)) {
        native.requestDeleteCapture(c.id);
        removed++;
      } else {
        kept.add(c);
      }
    }
    if (removed > 0) {
      _captures.clear();
      _captures.addAll(kept);
      _persist();
      notifyListeners();
    }
    return removed;
  }

  void _startWatching() {
    if (!_mounted) return;
    _subscription?.cancel();
    _subscription = native.captureEvents().listen(
      _onCaptureEvent,
      onError: (e) => debugPrint('ScreenSift: stream error: $e'),
    );
  }

  void _onCaptureEvent(Map<Object?, Object?> raw) {
    final id = (raw['id'] as num?)?.toInt() ?? 0;
    if (id == 0 || byId(id) != null) return;

    // `fromNativeMap` is the single conversion point for bridge rows so the
    // watcher event, the drain buffer and the recent-imports path all agree on
    // field names and defaults.
    final capture = SiftCapture.fromNativeMap(raw);

    _captures.insert(0, capture);
    _active = capture;
    _persist();
    notifyListeners();

    unawaited(_processCapture(capture));
  }

  Future<void> _processCapture(SiftCapture capture) async {
    if (!_mounted) return;
    _isProcessing = true;
    notifyListeners();
    SiftCapture updated;
    try {
      // The extractor needs a local copy of the image; the watcher only hands
      // over an id, so materialize first.
      final SiftCapture materialized = await _materialized(capture);
      final SiftExtraction extraction = await buildExtractor().extract(
        materialized,
      );
      updated = extraction.applyTo(materialized);
      _lastReady = updated;
      onCaptureReady?.call(updated);
    } catch (e, stack) {
      debugPrint('ScreenSift: extraction failed for #${capture.id}: $e');
      debugPrint(stack.toString());
      updated = capture.copyWith(
        status: ProcessingStatus.failed,
        errorMessage: '$e',
      );
      _lastError = '$e';
    }
    final idx = _captures.indexWhere((c) => c.id == capture.id);
    if (idx != -1) _captures[idx] = updated;
    _persist();
    _isProcessing = false;
    _active = null;
    if (_mounted) notifyListeners();
  }

  /// Copies the source image into the app-private cache exactly once.
  Future<SiftCapture> _materialized(SiftCapture capture) async {
    final String? cached = capture.cachedPath;
    if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
      return capture;
    }
    final String? path = await native.materializeCapture(capture.id);
    if (path == null || path.isEmpty) return capture;
    return capture.copyWith(cachedPath: path);
  }

  /// Re-runs extraction for a capture that previously failed.
  Future<void> retry(SiftCapture capture) async {
    final idx = _captures.indexWhere((c) => c.id == capture.id);
    if (idx == -1) return;
    final reset = _captures[idx].copyWith(
      status: ProcessingStatus.queued,
      clearError: true,
    );
    _captures[idx] = reset;
    _active = reset;
    notifyListeners();
    await _processCapture(reset);
  }

  /// One-time import of screenshots already on the device, newest first.
  Future<int> importRecent({int limit = 15}) async {
    final rows = await native.recentScreenshots(limit: limit);
    var added = 0;
    for (final raw in rows) {
      final id = (raw['id'] as num?)?.toInt() ?? 0;
      if (id == 0 || byId(id) != null) continue;
      final capture = SiftCapture.fromNativeMap(raw);
      _captures.insert(0, capture);
      added++;
      unawaited(_processCapture(capture));
    }
    if (added > 0) {
      _persist();
      notifyListeners();
    }
    return added;
  }

  Future<void> importFile(String path) async {
    if (_captures.any((c) => c.cachedPath == path || c.sourcePath == path)) {
      return;
    }
    final capture = SiftCapture(
      id: DateTime.now().microsecondsSinceEpoch,
      createdAt: DateTime.now(),
      name: path.split(Platform.pathSeparator).last,
      cachedPath: path,
      sourcePath: path,
    );
    _captures.insert(0, capture);
    _active = capture;
    _persist();
    notifyListeners();
    await _processCapture(capture);
  }

  /// Starts or stops the native watcher. Returns whether the OS accepted it.
  Future<bool> setWatchEnabled(bool value) async {
    final bool ok = value
        ? await native.startWatching()
        : await native.stopWatching();
    if (ok) {
      settings.watchEnabled = value;
      await _refreshPlatform();
    } else {
      _lastError = value
          ? 'Could not start the watcher.'
          : 'Could not stop the watcher.';
    }
    notifyListeners();
    return ok;
  }

  Future<void> _loadCaptures() async {
    final raw = prefs.getString(_capturesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <SiftCapture>[
        for (final row in decoded)
          if (row is Map) SiftCapture.fromJson(Map<String, Object?>.from(row)),
      ];
      if (loaded.length > _maxCaptures) {
        loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        loaded.removeRange(_maxCaptures, loaded.length);
      }
      _captures.clear();
      _captures.addAll(loaded);
      notifyListeners();
    } catch (e) {
      debugPrint('ScreenSift: load failed: $e');
      _captures.clear();
    }
  }

  Future<void> _persist() async {
    try {
      await prefs.setString(
        _capturesKey,
        jsonEncode(_captures.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ScreenSift: persist failed: $e');
    }
  }

  Future<void> _refreshPlatform() async {
    try {
      final raw = await native.platformInfo();
      _platform = PlatformSnapshot.fromMap(raw);
    } catch (e) {
      debugPrint('ScreenSift: platform info failed: $e');
    }
    if (_mounted) notifyListeners();
  }
}
