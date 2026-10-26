import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/sift_capture.dart';
import '../models/sift_category.dart';
import '../models/sift_intent.dart';
import 'capture_extractor.dart';

class RemoteExtractor implements CaptureExtractor {
  final String baseUrl;

  RemoteExtractor({required this.baseUrl});

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _pollDelay = Duration(seconds: 2);
  static const int _maxPollAttempts = 15;

  @override
  String get id => 'remote';

  @override
  String get label => 'Cloud model';

  @override
  bool get requiresNetwork => true;

  @override
  bool get isConfigured => baseUrl.trim().isNotEmpty;

  @override
  Future<SiftExtraction> extract(SiftCapture capture) async {
    final path = capture.cachedPath;
    if (path == null || path.isEmpty) {
      throw Exception('The screenshot has no local copy to upload.');
    }

    final data = await extractData(File(path));
    return SiftExtraction(
      intent: SiftIntent.fromWire(data['intent']),
      category: SiftCategory.fromWire(data['category']),
      title: data['title'] as String?,
      summary: data['summary'] as String?,
      amount: _parseAmount(data['amount']),
      currency: (data['currency'] as String?) ?? 'INR',
      upiId: data['upi_id'] as String?,
      payeeName: data['payee_name'] as String?,
      link: data['link'] as String?,
      dueAt: _parseDateTime(data['due_at']),
      referenceCode: data['reference_code'] as String?,
      tags: (data['tags'] as List<Object?>? ?? const <Object?>[])
          .map((tag) => '$tag')
          .toList(growable: false),
      confidence: _parseAmount(data['confidence']) ?? 0.7,
    );
  }

  // Tolerant numeric parsing for amounts sent as strings (e.g., "450", "₹450.00")
  double? _parseAmount(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final sanitized = raw.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(sanitized);
    }
    return null;
  }

  // Tolerant date parsing for ISO 8601 strings and Unix epoch integers
  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      // Determine if epoch is in seconds or milliseconds
      return raw < 10000000000
          ? DateTime.fromMillisecondsSinceEpoch(raw * 1000)
          : DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Future<Map<String, dynamic>> extractData(File imageFile) async {
    try {
      // 1. Request Presigned S3 URL
      final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final presignRes = await http
          .post(Uri.parse('$normalizedBaseUrl/presign'))
          .timeout(_requestTimeout);
      if (presignRes.statusCode != 200) {
        throw Exception(
          'Failed to get presign URL: HTTP ${presignRes.statusCode} '
          '${_responseSnippet(presignRes)}',
        );
      }

      final presignJson = _decodeObject(presignRes.body, 'presign response');

      // Handle snake_case vs camelCase
      final jobId = presignJson['job_id'] ?? presignJson['jobId'];
      final uploadUrl = presignJson['upload_url'] ?? presignJson['uploadUrl'];

      if (jobId == null || uploadUrl == null) {
        throw Exception("Invalid API response: missing jobId or uploadUrl");
      }

      // 2. Upload image to S3.
      final imageBytes = await imageFile.readAsBytes();
      final uploadRes = await http
          .put(
            Uri.parse('$uploadUrl'),
            headers: const <String, String>{'Content-Type': 'image/jpeg'},
            body: imageBytes,
          )
          .timeout(_requestTimeout);

      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 204) {
        throw Exception(
          'S3 image upload failed: HTTP ${uploadRes.statusCode} '
          '${_responseSnippet(uploadRes)}',
        );
      }

      // 3. Poll API Gateway for processed status
      return await _pollForStatus(jobId);
    } catch (e) {
      // Explicitly log this so the fallback to local ML Kit is not silent
      debugPrint('RemoteExtraction Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _pollForStatus(String jobId) async {
    for (int i = 0; i < _maxPollAttempts; i++) {
      await Future.delayed(_pollDelay);

      final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final statusRes = await http
          .get(Uri.parse('$normalizedBaseUrl/status/$jobId'))
          .timeout(_requestTimeout);
      if (statusRes.statusCode != 200) {
        debugPrint(
          'ScreenSift: status poll $jobId attempt ${i + 1} failed: '
          'HTTP ${statusRes.statusCode} ${_responseSnippet(statusRes)}',
        );
        continue;
      }

      final statusJson = _decodeObject(statusRes.body, 'status response');
      final status = statusJson['status']?.toString().toUpperCase();

      if (status == 'SUCCESS') {
        // Flatten nested result objects if necessary
        final result = statusJson['result'] ?? statusJson;

        return {
          'intent': result['intent'],
          'category': result['category'],
          'title': result['title'],
          'summary': result['summary'],
          'amount': _parseAmount(result['amount']),
          'currency': result['currency'],
          'upi_id': result['upi_id'] ?? result['upiId'],
          'payee_name': result['payee_name'] ?? result['payeeName'],
          'link': result['link'],
          'due_at': _parseDateTime(
            result['due_at'] ??
                result['date'] ??
                result['dueDate'] ??
                result['due_date'],
          ),
          'reference_code': result['reference_code'] ?? result['referenceCode'],
          'tags': result['tags'],
          'confidence': result['confidence'],
        };
      } else if (status == 'FAILED') {
        throw Exception(
          'Backend extraction failed for job $jobId: '
          '${statusJson['error'] ?? statusJson['message'] ?? 'no details'}',
        );
      }
    }

    throw Exception(
      'Polling timeout: job $jobId did not finish after '
      '${_maxPollAttempts * _pollDelay.inSeconds} seconds.',
    );
  }

  Map<String, dynamic> _decodeObject(String body, String label) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw Exception('Invalid JSON in $label: $error');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Invalid $label: expected a JSON object.');
  }

  String _responseSnippet(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return '';
    const maxLength = 300;
    return body.length <= maxLength
        ? body
        : '${body.substring(0, maxLength)}...';
  }
}
