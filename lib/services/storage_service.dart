import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a file (or bytes) to Firebase Storage and returns the download URL.
  static Future<String> uploadFile(
    dynamic fileData, {
    String folder = 'uploads',
    String? extension,
    String? originalFileName,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var ext = extension ?? '.jpg';
      if (ext.isNotEmpty && !ext.startsWith('.')) ext = '.$ext';
      final fileName = originalFileName ?? '$timestamp$ext';
      final fullPath = '$folder/$fileName';
      final ref = _storage.ref().child(fullPath);

      final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
      final metadata = SettableMetadata(contentType: mimeType);

      UploadTask uploadTask;
      if (fileData is Uint8List) {
        // Upload from bytes (e.g. Flutter Web or memory)
        uploadTask = ref.putData(fileData, metadata);
      } else if (fileData is File) {
        // Upload from File (e.g. Mobile)
        uploadTask = ref.putFile(fileData, metadata);
      } else {
        throw ArgumentError('fileData must be a File or Uint8List');
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage upload error: $e');
      throw Exception('Failed to upload file to Firebase Storage: $e');
    }
  }
}
