import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The only place in the Dart layer that knows the bridge exists.
///
/// Every call goes through [_invoke], which converts **all** channel failures
/// into `null` instead of throwing. The previous implementation only caught
/// `PlatformException`, so a missing handler surfaced as an uncaught
/// `MissingPluginException`, aborted `initState`, and left the app with no
/// listener attached at all.
class NativeScreenshotSource {
  NativeScreenshotSource({
    MethodChannel methodChannel =
        const MethodChannel('com.screensift/native'),
    EventChannel eventChannel =
        const EventChannel('com.screensift/screenshots'),
  })  : _method = methodChannel,
        _events = eventChannel;

  final MethodChannel _method;
  final EventChannel _events;

  static const String permissionMedia = 'media';
  static const String permissionNotifications = 'notifications';

  // --- watcher -------------------------------------------------------------

  /// Starts the foreground observer. Returns false when the OS refused to
  /// promote the service (common on Android 12+ from the background).
  Future<bool> startWatching() async =>
      await _invoke<bool>('startWatching') ?? false;

  Future<bool> stopWatching() async =>
      await _invoke<bool>('stopWatching') ?? false;

  Future<bool> isWatching() async => await _invoke<bool>('isWatching') ?? false;

  /// Captures the native observer saw but Dart never consumed.
  ///
  /// Reads *and clears* the buffer in one hop, so a capture cannot be replayed
  /// twice across cold starts.
  Future<List<Map<Object?, Object?>>> drainBufferedCaptures() async {
    final Object? raw = await _invoke<Object?>('drainBufferedCaptures');
    return _asMapList(raw);
  }

  Future<void> clearCaptureBuffer() =>
      _invoke<bool>('clearCaptureBuffer').then((_) {});

  /// Broadcast stream of new captures. Channel errors are logged, never
  /// rethrown, because one bad event must not tear down the subscription.
  Stream<Map<Object?, Object?>> captureEvents() {
    return _events.receiveBroadcastStream().transform(
          StreamTransformer<Object?, Map<Object?, Object?>>.fromHandlers(
            handleData: (Object? data, EventSink<Map<Object?, Object?>> sink) {
              if (data is Map) sink.add(data.cast<Object?, Object?>());
            },
            handleError: (
              Object error,
              StackTrace stackTrace,
              EventSink<Map<Object?, Object?>> sink,
            ) {
              debugPrint('ScreenSift: screenshot channel error: $error');
            },
          ),
        );
  }

  // --- permissions ---------------------------------------------------------

  Future<bool> hasPermission(String kind) async =>
      await _invoke<bool>('hasPermission', <String, Object?>{'kind': kind}) ??
      false;

  Future<bool> requestPermission(String kind) async =>
      await _invoke<bool>(
        'requestPermission',
        <String, Object?>{'kind': kind},
      ) ??
      false;

  Future<void> openAppSettings() =>
      _invoke<bool>('openAppSettings').then((_) {});

  // --- media ---------------------------------------------------------------

  /// Recent screenshots already on the device, newest first.
  Future<List<Map<Object?, Object?>>> recentScreenshots({int limit = 30}) async {
    final Object? raw = await _invoke<Object?>(
      'recentScreenshots',
      <String, Object?>{'limit': limit},
    );
    return _asMapList(raw);
  }

  /// Absolute path of an app-private copy of the image, or null.
  Future<String?> materializeCapture(int id) =>
      _invoke<String>('materializeCapture', <String, Object?>{'id': id});

  /// Deletes the capture, asking the OS for confirmation when it must.
  Future<bool> requestDeleteCapture(int id) async =>
      await _invoke<bool>(
        'requestDeleteCapture',
        <String, Object?>{'id': id},
      ) ??
      false;

  Future<void> purgeCache() => _invoke<bool>('purgeCache').then((_) {});

  // --- diagnostics ---------------------------------------------------------

  Future<Map<Object?, Object?>> platformInfo() async {
    final Object? raw = await _invoke<Object?>('platformInfo');
    return raw is Map ? raw.cast<Object?, Object?>() : <Object?, Object?>{};
  }

  // --- internals -----------------------------------------------------------

  /// Returns null for *any* failure: no handler, wrong types, or a native
  /// exception. Callers decide the fallback.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on MissingPluginException {
      debugPrint('ScreenSift: native bridge missing ($method).');
    } on PlatformException catch (error) {
      debugPrint('ScreenSift: $method failed: ${error.code} ${error.message}');
    } on TypeError catch (error) {
      debugPrint('ScreenSift: $method returned an unexpected type: $error');
    }
    return null;
  }

  List<Map<Object?, Object?>> _asMapList(Object? raw) {
    if (raw is! List) return const <Map<Object?, Object?>>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .toList(growable: false);
  }
}

/// Immutable facts about the device, reported by the native `platformInfo`
/// call. Surfaced in Settings and used to decide which permission dialogs to
/// show, without the Dart layer depending on `dart:io` Platform.
@immutable
class PlatformSnapshot {
  const PlatformSnapshot({
    this.sdk = 0,
    this.androidVersion = '',
    this.device = '',
    this.packageName = '',
    this.watcherRunning = false,
    this.watchEnabled = false,
  });

  final int sdk;
  final String androidVersion;
  final String device;
  final String packageName;
  final bool watcherRunning;
  final bool watchEnabled;

  static PlatformSnapshot fromMap(Map<Object?, Object?> raw) {
    return PlatformSnapshot(
      sdk: (raw['sdk'] as num?)?.toInt() ?? 0,
      androidVersion: raw['android'] is String ? raw['android']! as String : '',
      device: raw['device'] is String ? raw['device']! as String : '',
      packageName: raw['package'] is String ? raw['package']! as String : '',
      watcherRunning: raw['watcherRunning'] == true,
      watchEnabled: raw['watchEnabled'] == true,
    );
  }
}