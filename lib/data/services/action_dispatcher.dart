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
class ActionDispatcher {
  const ActionDispatcher({
    @visibleForTesting Future<bool> Function(Uri uri)? launch,
    @visibleForTesting Future<bool> Function(Event event)? addEvent,
  })  : _launchOverride = launch,
        _addEventOverride = addEvent;

  final Future<bool> Function(Uri uri)? _launchOverride;
  final Future<bool> Function(Event event)? _addEventOverride;

  bool canPay(SiftCapture capture) =>
      (capture.upiId?.isNotEmpty ?? false) && !capture.isFailed;

  bool canOpenLink(SiftCapture capture) =>
      (capture.link?.isNotEmpty ?? false) && !capture.isFailed;

  bool canSchedule(SiftCapture capture) =>
      capture.dueAt != null && !capture.isFailed;

  bool canAct(SiftCapture capture) =>
      canPay(capture) || canOpenLink(capture) || canSchedule(capture);

  // --- verbs ---------------------------------------------------------------

  /// Opens the user's UPI app with the payee, amount and note prefilled.
  Future<ActionOutcome> pay(SiftCapture capture) async {
    String? vpa = capture.upiId?.trim();
    if (vpa == null || vpa.isEmpty) return ActionOutcome.unsupported;

    // Fix: If Claude extracted a raw 10-digit phone number, UPI apps will 
    // silently reject the intent. We append a default handle to fix the format.
    if (RegExp(r'^\d{10}$').hasMatch(vpa)) {
      vpa = '$vpa@ybl';
    }

    // Construct the string manually so the "@" in the UPI ID does NOT get 
    // converted to "%40", which breaks GPay/PhonePe/Paytm.
    String urlString = 'upi://pay?pa=$vpa';
    
    if (capture.payeeName != null && capture.payeeName!.isNotEmpty) {
      urlString += '&pn=${Uri.encodeComponent(capture.payeeName!)}';
    }
    if (capture.amount != null) {
      urlString += '&am=${_amountParam(capture.amount!)}';
    }
    urlString += '&cu=${capture.currency.toUpperCase()}';
    urlString += '&tn=${Uri.encodeComponent(capture.displayTitle)}';

    final Uri uri = Uri.parse(urlString);
    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  /// Opens the extracted link in the browser.
  Future<ActionOutcome> openLink(SiftCapture capture) async {
    final String? raw = capture.link;
    if (raw == null || raw.isEmpty) return ActionOutcome.unsupported;
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return ActionOutcome.failed;

    final bool opened = await _launch(uri);
    return opened ? ActionOutcome.done : ActionOutcome.failed;
  }

  /// Opens the parcel's tracking page.
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

  static Future<bool> _defaultLaunch(Uri uri) async {
    try {
      // Fix: Reverted to externalApplication. Android 14 OEMs often block 
      // custom payment schemes if the non-browser requirement flag is forced.
      if (!await canLaunchUrl(uri)) {
        if (uri.scheme != 'upi') return false;
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('ScreenSift: launch failed for $uri: $error');
      return false;
    }
  }

  static String _amountParam(double amount) {
    // Many UPI apps strictly require exactly 2 decimal places. 
    // Returning '450' instead of '450.00' can crash the intent!
    return amount.toStringAsFixed(2);
  }
}