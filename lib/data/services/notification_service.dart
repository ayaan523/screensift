import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/sift_capture.dart';
import '../models/sift_intent.dart';
import 'action_dispatcher.dart';

class NotificationService {
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.dispatcher = const ActionDispatcher(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final ActionDispatcher dispatcher;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onTap,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> showAction(SiftCapture capture) async {
    await init();
    if (!capture.isActionable) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'screensift_actions',
        'ScreenSift actions',
        channelDescription: 'Actionable screenshot intents',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.recommendation,
      ),
    );

    await _plugin.show(
      id: capture.id,
      title: _title(capture),
      body: _body(capture),
      notificationDetails: details,
      payload: jsonEncode(capture.toJson()),
    );
  }

  Future<void> _onTap(NotificationResponse response) async {
    final String? payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final capture = SiftCapture.fromJson(Map<String, Object?>.from(decoded));
      switch (capture.intent) {
        case SiftIntent.payment:
          await dispatcher.pay(capture);
        case SiftIntent.event:
        case SiftIntent.reminder:
          await dispatcher.schedule(capture);
        case SiftIntent.link:
          await dispatcher.openLink(capture);
        default:
          break;
      }
    } catch (error) {
      debugPrint('ScreenSift: notification tap failed: $error');
    }
  }

  String _title(SiftCapture capture) => switch (capture.intent) {
    SiftIntent.payment => 'Payment detected',
    SiftIntent.event => 'Calendar event detected',
    SiftIntent.reminder => 'Reminder detected',
    SiftIntent.link => 'Link detected',
    _ => 'Screenshot processed',
  };

  String _body(SiftCapture capture) => switch (capture.intent) {
    SiftIntent.payment =>
      'Pay ${capture.amountLabel ?? ''} to ${capture.upiId ?? capture.payeeName ?? 'recipient'}',
    SiftIntent.event || SiftIntent.reminder => capture.displayTitle,
    SiftIntent.link => capture.link ?? capture.displayTitle,
    _ => capture.displayTitle,
  };
}
