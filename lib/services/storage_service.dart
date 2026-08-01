import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'media_reference_policy.dart';

class ManagedMediaAsset {
  final String assetId;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;

  const ManagedMediaAsset({
    required this.assetId,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
  });
}

/// Uploads user-generated media only to paths protected by storage.rules.
class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Uuid _uuid = Uuid();

  /// Runs a reference write and removes a newly uploaded object only when the
  /// write fails deterministically. Ambiguous network failures leave the
  /// pending asset for the server-side reconciler; deleting it here could
  /// race a write that was accepted remotely. The caller must provide the
  /// failure classifier so an unrecognized error fails closed.
  static Future<void> commitReferenceOrCleanup({
    required Future<void> Function() commit,
    required Future<void> Function() cleanup,
    required bool Function(Object error) shouldCleanup,
  }) async {
    try {
      await commit();
    } catch (error) {
      if (shouldCleanup(error)) {
        try {
          await cleanup();
        } catch (_) {
          // The original reference error is more actionable. The pending
          // managed asset remains eligible for the scheduled reconciler.
        }
      }
      rethrow;
    }
  }

  /// Deletes an uploaded profile/cover object that has not been committed to
  /// its owning Firestore document. The path must be canonical and scoped to
  /// the authenticated account/group before a destructive call is made.
  static Future<void> deleteUncommittedAsset({
    required String storagePath,
    required String ownerId,
    String? groupId,
  }) async {
    final isProfilePhoto = isCanonicalProfilePhotoPath(storagePath, ownerId);
    final isGroupCover =
        groupId != null && isCanonicalGroupCoverPath(storagePath, groupId);
    if (!isProfilePhoto && !isGroupCover) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Only an account/group-scoped managed asset can be discarded.',
      );
    }

    try {
      await _storage.ref().child(storagePath).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  /// Returns false for failures where a callable/write may have committed
  /// remotely even though the client did not receive an acknowledgement.
  static bool shouldCleanupAfterReferenceFailure(String? errorCode) {
    return !const {
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'internal',
      'network-request-failed',
      'unavailable',
      'unknown',
    }.contains(errorCode);
  }

  static Future<String> uploadProfileImage({
    required Uint8List bytes,
    required String userId,
    String extension = 'jpg',
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'The upload cannot be empty.');
    }
    final path = 'users/$userId/profile/${_assetName(extension)}';
    final assetId = _managedAssetIdForPath(path);
    final contentType = _imageContentType(extension);
    await _storage
        .ref()
        .child(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: {'assetId': assetId, 'ownerId': userId},
            cacheControl: 'private,no-store',
          ),
        );
    await _waitForManagedAsset(
      assetId: assetId,
      storagePath: path,
      ownerId: userId,
      fallbackMimeType: contentType,
      fallbackSizeBytes: bytes.length,
    );
    return path;
  }

  static Future<String> uploadGroupCover({
    required Uint8List bytes,
    required String groupId,
    required String ownerId,
    String extension = 'jpg',
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'The upload cannot be empty.');
    }
    final path = 'groups/$groupId/covers/${_assetName(extension)}';
    final assetId = _managedAssetIdForPath(path);
    final contentType = _imageContentType(extension);
    await _storage
        .ref()
        .child(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: {
              'assetId': assetId,
              'ownerId': ownerId,
              'groupId': groupId,
            },
            cacheControl: 'private,no-store',
          ),
        );
    await _waitForManagedAsset(
      assetId: assetId,
      storagePath: path,
      ownerId: ownerId,
      fallbackMimeType: contentType,
      fallbackSizeBytes: bytes.length,
    );
    return path;
  }

  static Future<ManagedMediaAsset> uploadMessageAsset({
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
    final path = 'groups/$groupId/messages/$messageId/$resolvedAssetId';
    final managedAssetId = _managedAssetIdForPath(path);
    return _uploadManagedMessageAsset(
      bytes: bytes,
      path: path,
      contentType: contentType,
      metadata: {
        'assetId': managedAssetId,
        'ownerId': ownerId,
        'groupId': groupId,
        'messageId': messageId,
      },
      managedAssetId: managedAssetId,
      ownerId: ownerId,
    );
  }

  static Future<ManagedMediaAsset> _uploadManagedMessageAsset({
    required Uint8List bytes,
    required String path,
    required String contentType,
    required Map<String, String> metadata,
    required String managedAssetId,
    required String ownerId,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'The upload cannot be empty.');
    }
    final reference = _storage.ref().child(path);
    try {
      final existing = await reference.getMetadata();
      if (existing.customMetadata?['assetId'] != managedAssetId ||
          existing.customMetadata?['ownerId'] != ownerId) {
        throw StateError('The existing managed asset identity does not match.');
      }
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          customMetadata: metadata,
          cacheControl: 'private,no-store',
        ),
      );
    }

    return _waitForManagedAsset(
      assetId: managedAssetId,
      storagePath: path,
      ownerId: ownerId,
      fallbackMimeType: contentType,
      fallbackSizeBytes: bytes.length,
    );
  }

  static Future<ManagedMediaAsset> _waitForManagedAsset({
    required String assetId,
    required String storagePath,
    required String ownerId,
    required String fallbackMimeType,
    required int fallbackSizeBytes,
  }) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      final snapshot = await _firestore
          .collection('managed_assets')
          .doc(assetId)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data != null) {
        if (data['storagePath'] != storagePath ||
            data['ownerUid'] != ownerId ||
            !const ['pending', 'committed'].contains(data['status'])) {
          throw StateError('Managed asset registration is inconsistent.');
        }
        return ManagedMediaAsset(
          assetId: assetId,
          storagePath: storagePath,
          mimeType: data['mimeType']?.toString() ?? fallbackMimeType,
          sizeBytes: data['sizeBytes'] is num
              ? (data['sizeBytes'] as num).toInt()
              : fallbackSizeBytes,
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
    throw StateError('Managed asset registration timed out.');
  }

  static String _managedAssetIdForPath(String storagePath) {
    return base64Url.encode(utf8.encode(storagePath)).replaceAll('=', '');
  }

  static String _assetName(String extension) {
    final normalized = extension.toLowerCase().replaceAll('.', '');
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Unsupported file extension.',
      );
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
        throw ArgumentError.value(
          extension,
          'extension',
          'Unsupported image type.',
        );
    }
  }
}
