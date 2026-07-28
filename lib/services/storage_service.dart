import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Uploads user-generated media only to paths protected by storage.rules.
class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const Uuid _uuid = Uuid();

  static Future<String> uploadProfileImage({
    required Uint8List bytes,
    required String userId,
    String extension = 'jpg',
  }) {
    return _upload(
      bytes: bytes,
      path: 'users/$userId/profile/${_assetName(extension)}',
      contentType: _imageContentType(extension),
      metadata: {'ownerId': userId},
    );
  }

  static Future<String> uploadGroupCover({
    required Uint8List bytes,
    required String groupId,
    required String ownerId,
    String extension = 'jpg',
  }) {
    return _upload(
      bytes: bytes,
      path: 'groups/$groupId/covers/${_assetName(extension)}',
      contentType: _imageContentType(extension),
      metadata: {'ownerId': ownerId, 'groupId': groupId},
    );
  }

  static Future<String> uploadMessageAsset({
    required Uint8List bytes,
    required String groupId,
    required String messageId,
    required String ownerId,
    required String extension,
    required String contentType,
    String? assetId,
  }) {
    final resolvedAssetId = assetId ?? _assetName(extension);
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,160}$').hasMatch(resolvedAssetId)) {
      throw ArgumentError.value(assetId, 'assetId', 'Invalid asset ID.');
    }
    return _uploadImmutable(
      bytes: bytes,
      path:
          'groups/$groupId/messages/$messageId/$resolvedAssetId',
      contentType: contentType,
      metadata: {
        'ownerId': ownerId,
        'groupId': groupId,
        'messageId': messageId,
      },
    );
  }

  static Future<String> _upload({
    required Uint8List bytes,
    required String path,
    required String contentType,
    required Map<String, String> metadata,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'The upload cannot be empty.');
    }

    final reference = _storage.ref().child(path);
    final snapshot = await reference.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: metadata,
        cacheControl: 'private,max-age=31536000,immutable',
      ),
    );
    return snapshot.ref.getDownloadURL();
  }

  static Future<String> _uploadImmutable({
    required Uint8List bytes,
    required String path,
    required String contentType,
    required Map<String, String> metadata,
  }) async {
    final reference = _storage.ref().child(path);
    try {
      return await reference.getDownloadURL();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
    return _upload(
      bytes: bytes,
      path: path,
      contentType: contentType,
      metadata: metadata,
    );
  }

  static String _assetName(String extension) {
    final normalized = extension.toLowerCase().replaceAll('.', '');
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(normalized)) {
      throw ArgumentError.value(extension, 'extension', 'Unsupported file extension.');
    }
    return '${_uuid.v4()}.$normalized';
  }

  static String _imageContentType(String extension) {
    switch (extension.toLowerCase().replaceAll('.', '')) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        throw ArgumentError.value(extension, 'extension', 'Unsupported image type.');
    }
  }
}
