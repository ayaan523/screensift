import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AwsService {
  // TODO: Replace this with your actual AWS API Gateway endpoint url later!
  static const String apiUrl = 'https://YOUR_API_GATEWAY_URL.execute-api.us-east-1.amazonaws.com/prod/extract';

  /// Takes the file path from the Kotlin background watcher and sends it to AWS
  static Future<Map<String, dynamic>?> extractIntentFromScreenshot(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print("File not found at $imagePath");
        return null;
      }

      // Read the image and convert to Base64
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Send to AWS API Gateway
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          // 'x-api-key': 'YOUR_API_KEY_IF_NEEDED',
        },
        body: jsonEncode({
          'image_base64': base64Image,
        }),
      );

      if (response.statusCode == 200) {
        // We expect AWS Lambda to return structured JSON like:
        // { "type": "upi", "upi_id": "merchant@sbi", "amount": "500", "merchant_name": "Cafe" }
        return jsonDecode(response.body);
      } else {
        print("AWS Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("Network/Parsing Exception: $e");
      return null;
    }
  }
}