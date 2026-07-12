import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CloudinaryService {
  // Provided by user
  static const String cloudName = 'j6yzhocm';
  
  // Provided by user
  static const String uploadPreset = 'bsgc-app';

  static Future<String?> uploadFile(Uint8List bytes, {String resourceType = 'auto', String extension = 'jpg'}) async {
    if (cloudName == 'YOUR_CLOUD_NAME' || uploadPreset == 'YOUR_UPLOAD_PRESET') {
      debugPrint('Cloudinary credentials not set. Upload aborted.');
      return null;
    }

    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'upload_${DateTime.now().millisecondsSinceEpoch}.$extension',
          ),
        );

      final response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = jsonDecode(responseString);
        return jsonMap['secure_url'];
      } else {
        debugPrint('Cloudinary upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Cloudinary upload error: $e');
      return null;
    }
  }
}
