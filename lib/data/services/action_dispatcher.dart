import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sift_capture.dart';

/// The result of trying to run an action, phrased for the UI.
enum ActionOutcome {
  /// The OS accepted and something visible happened.
  done,

  /// We cannot do this for this capture (no VPA, no date, no link).
  unsupported,

  /// We tried and the platform refused, or nothing could handle it.
  failed,
}

/// Executes the "verb" half of a capture: paying, adding to the calendar,
/// opening a link, checking a parcel.
///
/// Kept free of Flutter widgets so it can be unit-tested by injecting the
/// launcher and calendar hooks.
class ActionDispatcher {
  const ActionDispatcher({
    @visibleForTesting Future<bool> Function(Uri uri)? launch,
    @visibleForTesting Future<bool> Function(Event event)? addEvent,
  })  : _launchOverride = launch,
        _addEventOverride = addEvent;

  final Future<bool> Function(Uri uri)? _launchOverride;
  final Future<bool> Function(Event event)? _addEventOverride;

  /// True when this capture can be paid.
  bool canPay(SiftCapture capture) =>
      (capture.upiId?.isNotEmpty ?? false) && !capture.isFailed;

  bool canOpenLink(SiftCapture capture) =>
      (capture.link?.isNotEmpty ?? false) && !capture.isFailed;

  bool canSchedule(SiftCapture capture) =>
      capture.dueAt != null && !capture.isFailed;

  /// True when the capture has at least one executable verb.
  bool canAct(SiftCapture capture) =>
      canPay(capture) || canOpenLink(capture) || canSchedule(capture);

  // --- verbs ---------------------------------------------------------------

  /// Opens the user's UPI app with the payee, amount and note prefilled.
  ///
  /// This is a *request* into the payment app; ScreenSift never sees a PIN,
  /// a balance, or the outcome of the transfer.
  Future<ActionOutcome> pay(SiftCapture capture) async {
    final String? vpa = capture.upiId;
    if (vpa == null || vpa.isEmpty) return ActionOutcome.unsupported;

    final Map<String, String> params = <String, String>{
      'pa': vpa,
      if (capture.payeeName != null && capture.payeeName!.isNotEmpty)
        'pn': capture.payeeName!,
      if (capture.amount != null) 'am': _amountParam(capture.amount!),
      'cu': capture.currency.toUpperCase(),
      'tn': capture.displayTitle,
    };

    final Uri uri = Uri(scheme: 'upi', host: 'pay', queryParameters: params);
    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  /// Opens the extracted link in the browser (or the app that owns it).
  Future<ActionOutcome> openLink(SiftCapture capture) async {
    final String? raw = capture.link;
    if (raw == null || raw.isEmpty) return ActionOutcome.unsupported;
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return ActionOutcome.failed;

    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  /// Opens the parcel's tracking page. Uses the extracted link when we have
  /// one, otherwise a search that works with any courier.
  Future<ActionOutcome> track(SiftCapture capture) async {
    final String query = capture.referenceCode ?? capture.displayTitle;
    final Uri uri = Uri.https('www.google.com', '/search', <String, String>{
      'q': 'track $query',
    });
    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  /// Inserts an event into the user's calendar.
  Future<ActionOutcome> schedule(SiftCapture capture) async {
    final DateTime? start = capture.dueAt;
    if (start == null) return ActionOutcome.unsupported;

    final Event event = Event(
      title: capture.displayTitle,
      description: capture.summary ?? 'Captured by ScreenSift',
      location: capture.link,
      startDate: start,
      endDate: start.add(const Duration(hours: 1)),
    );

    final Future<bool> Function(Event) add =
        _addEventOverride ?? Add2Calendar.addEvent2Cal;
    try {
      final bool added = await add(event);
      return added ? ActionOutcome.done : ActionOutcome.failed;
    } catch (error) {
      debugPrint('ScreenSift: could not add calendar event: $error');
      return ActionOutcome.failed;
    }
  }

  /// Opens a maps or web search for a query.
  Future<ActionOutcome> search(String query) async {
    if (query.trim().isEmpty) return ActionOutcome.unsupported;
    final Uri uri = Uri.https('www.google.com', '/search', <String, String>{
      'q': query.trim(),
    });
    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  // --- internals -----------------------------------------------------------

  Future<bool> _launch(Uri uri) async {
    final Future<bool> Function(Uri) launcher =
        _launchOverride ?? _defaultLaunch;
    try {
      return await launcher(uri);
    } catch (error) {
      debugPrint('ScreenSift: could not launch $uri: $error');
      return false;
    }
  }

  /// `canLaunchUrl` then `launchUrl`, in external-application mode so links
  /// leave the app instead of silently failing inside a webview.
  static Future<bool> _defaultLaunch(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) {
        // A few UPI apps do not answer the probe but still handle the intent,
        // so a negative result is not treated as final for custom schemes.
        if (uri.scheme != 'upi') return false;
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('ScreenSift: launch failed for $uri: $error');
      return false;
    }
  }

  /// UPI wants a plain decimal string; scientific notation breaks the intent.
  static String _amountParam(double amount) {
    final bool isWhole = amount == amount.roundToDouble();
    return isWhole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }
}