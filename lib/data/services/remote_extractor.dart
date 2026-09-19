import 'package:dio/dio.dart';

import '../models/sift_capture.dart';
import '../models/sift_category.dart';
import '../models/sift_intent.dart';
import 'capture_extractor.dart';

/// Raised when the cloud path cannot produce an extraction.
///
/// Distinct from a transport error so the repository can show a useful message
/// and fall back to the on-device engine instead of failing the capture.
class ExtractionException implements Exception {
  const ExtractionException(this.message);

  final String message;

  @override
  String toString() => 'ExtractionException: $message';
}

/// Calls the ScreenSift extraction API (presign → S3 upload → status polling).
///
/// Dormant by default: [isConfigured] is false until the user sets an endpoint
/// in Settings, so the app never phones home out of the box. The wire contract
/// is a single multipart POST so it can be backed by a Lambda, a container, or
/// a Bedrock proxy without changing this class.
///
/// Presign  – `POST {endpoint}/presign`
/// Upload   – `PUT {uploadUrl}`
/// Poll     – `GET {endpoint}/status/{jobId}` every 1.5s
/// Success payload:
/// ```json
/// {
///   "intent": "PAYMENT", "category": "FINANCE",
///   "title": "Pay ₹450 to Rahul", "summary": "…",
///   "amount": 450, "currency": "INR",
///   "upi_id": "rahul@okhdfcbank", "payee_name": "Rahul",
///   "link": null, "due_at": 1760000000000,
///   "reference_code": null, "tags": ["Money"], "confidence": 0.92
/// }
/// ```
class RemoteExtractor implements CaptureExtractor {
  RemoteExtractor({
    required this.endpoint,
    required this.apiKey,
    Dio? dio,
    this.timeout = const Duration(seconds: 30),
  }) : _dio = dio ?? Dio();

  final String endpoint;
  final String apiKey;
  final Duration timeout;
  final Dio _dio;

  @override
  String get id => 'remote';

  @override
  String get label => 'Cloud model';

  @override
  bool get requiresNetwork => true;

  @override
  bool get isConfigured => endpoint.trim().isNotEmpty;

  @override
  Future<SiftExtraction> extract(SiftCapture capture) async {
    if (!isConfigured) {
      throw const ExtractionException('No extraction endpoint is configured.');
    }
    final String? imagePath = capture.cachedPath;
    if (imagePath == null || imagePath.isEmpty) {
      throw const ExtractionException(
        'The screenshot has no local copy to upload.',
      );
    }

    final Map<Object?, Object?> presign = await _presign(capture);
    final String uploadUrl =
        _string(presign['uploadUrl']) ?? _string(presign['upload_url']) ?? '';
    final String jobId =
        _string(presign['jobId']) ??
        _string(presign['job_id']) ??
        '${capture.id}';
    if (uploadUrl.isEmpty) {
      throw const ExtractionException(
        'The server did not return an upload URL.',
      );
    }
    await _upload(uploadUrl, imagePath);
    return _poll(jobId);
  }

  Future<Map<Object?, Object?>> _presign(SiftCapture capture) async {
    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        _resolve('presign'),
        data: <String, Object?>{
          'capture_id': capture.id,
          'name': capture.name,
          'content_type': 'image/png',
          'captured_at': capture.createdAt.toIso8601String(),
        },
        options: Options(
          headers: <String, String>{
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
            'Accept': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
    } on DioException catch (error) {
      throw ExtractionException(_describe(error));
    }
    final Object? body = response.data;
    if (body is! Map) {
      throw const ExtractionException(
        'The server returned an unexpected response.',
      );
    }
    return body.cast<Object?, Object?>();
  }

  Future<void> _upload(String uploadUrl, String imagePath) async {
    try {
      await _dio.put<Object?>(
        uploadUrl,
        data: MultipartFile.fromFileSync(imagePath).finalize(),
        options: Options(
          headers: <String, String>{'Content-Type': 'image/png'},
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
    } on DioException catch (error) {
      throw ExtractionException(_describe(error));
    }
  }

  Future<SiftExtraction> _poll(String jobId) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final Response<Object?> response;
      try {
        response = await _dio.get<Object?>(
          _resolve('status/$jobId'),
          options: Options(
            headers: <String, String>{
              if (apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${apiKey.trim()}',
              'Accept': 'application/json',
            },
            receiveTimeout: timeout,
          ),
        );
      } on DioException catch (error) {
        throw ExtractionException(_describe(error));
      }
      final Object? body = response.data;
      if (body is! Map) continue;
      final map = body.cast<Object?, Object?>();
      final String state =
          (_string(map['status']) ?? _string(map['state']) ?? '').toUpperCase();
      if (state == 'FAILED' || state == 'ERROR') {
        throw const ExtractionException(
          'The extraction service failed this capture.',
        );
      }
      if (state == 'SUCCESS' || state == 'READY' || map.containsKey('intent')) {
        final result = map['result'] ?? map['data'] ?? map;
        if (result is Map) {
          return _fromResponse(result.cast<Object?, Object?>());
        }
      }
    }
    throw const ExtractionException(
      'The extraction service did not finish in time.',
    );
  }

  String _resolve(String path) {
    final String base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  String _describe(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The extraction service took too long to respond.',
      DioExceptionType.connectionError =>
        'Could not reach the extraction service.',
      DioExceptionType.badResponse =>
        'The extraction service rejected the request '
            '(${error.response?.statusCode ?? 'unknown'}).',
      _ => 'The extraction request failed.',
    };
  }

  SiftExtraction _fromResponse(Map<Object?, Object?> body) {
    final Object? dueAt = body['due_at'];
    final Object? amount = body['amount'];
    final Object? confidence = body['confidence'];

    return SiftExtraction(
      intent: SiftIntent.fromWire(body['intent']),
      category: SiftCategory.fromWire(body['category']),
      title: _string(body['title']),
      summary: _string(body['summary']),
      amount: amount is num ? amount.toDouble() : null,
      currency: _string(body['currency']) ?? 'INR',
      upiId: _string(body['upi_id']),
      payeeName: _string(body['payee_name']),
      link: _string(body['link']),
      dueAt: dueAt is num
          ? DateTime.fromMillisecondsSinceEpoch(dueAt.toInt())
          : null,
      referenceCode: _string(body['reference_code']),
      tags: (body['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? tag) => '$tag')
          .toList(growable: false),
      confidence: confidence is num
          ? confidence.toDouble().clamp(0.0, 1.0)
          : 0.5,
    );
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
