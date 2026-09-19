import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which extraction engine the app should use.
enum ExtractorMode {
  /// Regex and heuristic parsing inside the app. Works offline, ships today,
  /// and is the default.
  onDevice('ON_DEVICE', 'On device', 'Works offline, nothing leaves the phone.'),

  /// Sends the image to the configured ScreenSift API (presign → S3 →
  /// extraction). Dormant until [SettingsStore.remoteEndpoint] is set.
  remote('REMOTE', 'Cloud model', 'Sends screenshots to your ScreenSift API.');

  const ExtractorMode(this.wireName, this.label, this.description);

  final String wireName;
  final String label;
  final String description;

  static ExtractorMode fromWire(Object? value) {
    if (value is! String) return ExtractorMode.onDevice;
    final String normalized = value.trim().toUpperCase();
    for (final ExtractorMode mode in ExtractorMode.values) {
      if (mode.wireName == normalized) return mode;
    }
    return ExtractorMode.onDevice;
  }
}

/// Device-local preferences, backed by `SharedPreferences`.
///
/// All fields are read once into memory at startup so the UI never awaits a
/// disk hit mid-frame; writes update memory first and persist behind the UI.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs) {
    _watchEnabled = _prefs.getBool(_kWatchEnabled) ?? true;
    _autoTrash = _prefs.getBool(_kAutoTrash) ?? false;
    _notifyOnCapture = _prefs.getBool(_kNotify) ?? true;
    _onboardingComplete = _prefs.getBool(_kOnboarding) ?? false;
    _hapticsEnabled = _prefs.getBool(_kHaptics) ?? true;
    _extractorMode = ExtractorMode.fromWire(_prefs.getString(_kExtractorMode));
    _remoteEndpoint = _prefs.getString(_kRemoteEndpoint) ?? '';
    _remoteApiKey = _prefs.getString(_kRemoteApiKey) ?? '';
    _retentionDays = _prefs.getInt(_kRetention) ?? 0;
  }

  /// Public entry point for the app bootstrap, which already holds a ready
  /// [SharedPreferences]. Also lets tests construct a store around a mock.
  SettingsStore.withPrefs(SharedPreferences prefs) : this._(prefs);

  static Future<SettingsStore> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SettingsStore._(prefs);
  }

  final SharedPreferences _prefs;

  static const String _kWatchEnabled = 'watch_enabled';
  static const String _kAutoTrash = 'auto_trash';
  static const String _kNotify = 'notify_on_capture';
  static const String _kOnboarding = 'onboarding_complete';
  static const String _kHaptics = 'haptics_enabled';
  static const String _kExtractorMode = 'extractor_mode';
  static const String _kRemoteEndpoint = 'remote_endpoint';
  static const String _kRemoteApiKey = 'remote_api_key';
  static const String _kRetention = 'retention_days';

  bool _watchEnabled = true;
  bool _autoTrash = false;
  bool _notifyOnCapture = true;
  bool _onboardingComplete = false;
  bool _hapticsEnabled = true;
  ExtractorMode _extractorMode = ExtractorMode.onDevice;
  String _remoteEndpoint = '';
  String _remoteApiKey = '';
  int _retentionDays = 0;

  bool get watchEnabled => _watchEnabled;
  bool get autoTrash => _autoTrash;
  bool get notifyOnCapture => _notifyOnCapture;
  bool get onboardingComplete => _onboardingComplete;
  bool get hapticsEnabled => _hapticsEnabled;
  ExtractorMode get extractorMode => _extractorMode;
  String get remoteEndpoint => _remoteEndpoint;
  String get remoteApiKey => _remoteApiKey;

  /// `0` means keep everything.
  int get retentionDays => _retentionDays;

  bool get canUseRemoteExtractor =>
      _extractorMode == ExtractorMode.remote && _remoteEndpoint.trim().isNotEmpty;

  set watchEnabled(bool value) => _setBool(_kWatchEnabled, value, () => _watchEnabled = value);

  set autoTrash(bool value) => _setBool(_kAutoTrash, value, () => _autoTrash = value);

  set notifyOnCapture(bool value) =>
      _setBool(_kNotify, value, () => _notifyOnCapture = value);

  set hapticsEnabled(bool value) =>
      _setBool(_kHaptics, value, () => _hapticsEnabled = value);

  set onboardingComplete(bool value) =>
      _setBool(_kOnboarding, value, () => _onboardingComplete = value);

  set extractorMode(ExtractorMode value) {
    if (_extractorMode == value) return;
    _extractorMode = value;
    _prefs.setString(_kExtractorMode, value.wireName);
    notifyListeners();
  }

  set remoteEndpoint(String value) {
    final String trimmed = value.trim();
    if (_remoteEndpoint == trimmed) return;
    _remoteEndpoint = trimmed;
    _prefs.setString(_kRemoteEndpoint, trimmed);
    notifyListeners();
  }

  set remoteApiKey(String value) {
    if (_remoteApiKey == value) return;
    _remoteApiKey = value;
    _prefs.setString(_kRemoteApiKey, value);
    notifyListeners();
  }

  set retentionDays(int value) {
    if (_retentionDays == value) return;
    _retentionDays = value;
    _prefs.setInt(_kRetention, value);
    notifyListeners();
  }

  void _setBool(String key, bool value, VoidCallback apply) {
    apply();
    _prefs.setBool(key, value);
    notifyListeners();
  }
}