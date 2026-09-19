import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Turns an image on disk into text.
///
/// Deliberately narrow so the pipeline can be exercised in unit tests with a
/// fake reader, and so a device without OCR still degrades gracefully instead
/// of failing the whole capture.
///
/// Named `ImageTextReader` rather than `TextRecognizer` because ML Kit already
/// exports a `TextRecognizer` and the two would collide at every import site.
abstract interface class ImageTextReader {
  /// Returns the recognised text, or an empty string when unavailable.
  Future<String> read(String imagePath);

  Future<void> dispose();
}

/// Used when OCR is unavailable. Extraction then falls back to filename
/// heuristics, which is still better than dropping the capture.
class NoopTextReader implements ImageTextReader {
  const NoopTextReader();

  @override
  Future<String> read(String imagePath) async => '';

  @override
  Future<void> dispose() async {}
}

/// ML Kit Latin text recognition, running entirely on device.
///
/// The Latin model ships inside the app bundle, which is what makes the
/// "nothing leaves your phone" promise real for the default extractor.
class MlKitTextReader implements ImageTextReader {
  MlKitTextReader({this._script = TextRecognitionScript.latin});

  final TextRecognitionScript _script;
  TextRecognizer? _recognizer;

  TextRecognizer get _instance =>
      _recognizer ??= TextRecognizer(script: _script);

  @override
  Future<String> read(String imagePath) async {
    if (imagePath.isEmpty) return '';
    try {
      final InputImage input = InputImage.fromFilePath(imagePath);
      final RecognizedText result = await _instance.processImage(input);
      // Newlines are kept on purpose: they are what let the rule engine treat
      // the first real line as a title.
      return result.text.trim();
    } catch (error) {
      debugPrint('ScreenSift: OCR failed for $imagePath: $error');
      return '';
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
