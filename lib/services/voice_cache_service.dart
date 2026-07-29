import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

enum VoiceCacheFailureKind {
  unsupported,
  authorization,
  missing,
  offlineMiss,
  transient,
}

class VoiceCacheException implements Exception {
  final VoiceCacheFailureKind kind;
  final String message;
  final Object? cause;

  const VoiceCacheException(this.kind, this.message, {this.cause});

  @override
  String toString() => message;
}

class VoiceHttpException implements Exception {
  final int statusCode;

  const VoiceHttpException({required this.statusCode});
}

VoiceCacheFailureKind classifyVoiceCacheFailure(
  Object error, {
  required bool hasCachedFile,
}) {
  if (error is VoiceCacheException) return error.kind;
  if (error is FormatException) return VoiceCacheFailureKind.unsupported;
  if (error is FirebaseException) {
    return switch (error.code) {
      'unauthorized' ||
      'unauthenticated' => VoiceCacheFailureKind.authorization,
      'object-not-found' => VoiceCacheFailureKind.missing,
      'retry-limit-exceeded' || 'unknown' =>
        hasCachedFile
            ? VoiceCacheFailureKind.transient
            : VoiceCacheFailureKind.offlineMiss,
      _ => VoiceCacheFailureKind.transient,
    };
  }
  if (error is VoiceHttpException) {
    if (error.statusCode == HttpStatus.unauthorized ||
        error.statusCode == HttpStatus.forbidden) {
      return VoiceCacheFailureKind.authorization;
    }
    if (error.statusCode == HttpStatus.notFound ||
        error.statusCode == HttpStatus.gone) {
      return VoiceCacheFailureKind.missing;
    }
    return VoiceCacheFailureKind.transient;
  }
  if (error is SocketException || error is TimeoutException) {
    return hasCachedFile
        ? VoiceCacheFailureKind.transient
        : VoiceCacheFailureKind.offlineMiss;
  }
  return VoiceCacheFailureKind.transient;
}

class VoiceCacheProgress {
  final int receivedBytes;
  final int? totalBytes;

  const VoiceCacheProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }
}

class VoiceDownloadResponse {
  final int? contentLength;
  final Stream<List<int>> bytes;

  const VoiceDownloadResponse({
    required this.contentLength,
    required this.bytes,
  });
}

class VoiceCacheEntry {
  final File file;
  final int byteLength;
  final bool wasCached;

  const VoiceCacheEntry({
    required this.file,
    required this.byteLength,
    required this.wasCached,
  });
}

abstract interface class VoiceCacheRepository {
  Future<VoiceCacheEntry?> lookup({
    required String accountId,
    required String sourceUrl,
  });

  Future<VoiceCacheEntry> prepare({
    required String accountId,
    required String sourceUrl,
    void Function(VoiceCacheProgress progress)? onProgress,
  });
}

typedef VoiceDownload = Future<VoiceDownloadResponse> Function(Uri uri);
typedef VoiceCacheRootProvider = Future<Directory> Function(String accountId);

class VoiceCacheService implements VoiceCacheRepository {
  static final VoiceCacheService shared = VoiceCacheService();

  VoiceCacheService({
    this.maxBytes = 50 * 1024 * 1024,
    this.expiry = const Duration(days: 14),
    DateTime Function()? now,
    this.cacheRootProvider,
    VoiceDownload? download,
  }) : _now = now ?? DateTime.now,
       _download = download ?? _downloadWithHttpClient;

  final int maxBytes;
  final Duration expiry;
  final DateTime Function() _now;
  final VoiceCacheRootProvider? cacheRootProvider;
  final VoiceDownload _download;
  final Map<String, Future<VoiceCacheEntry>> _inFlight = {};
  final Map<String, int> _accountGenerations = {};

  static const _supportedExtensions = {
    'aac',
    'm4a',
    'mp3',
    'ogg',
    'opus',
    'wav',
    'webm',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  @override
  Future<VoiceCacheEntry?> lookup({
    required String accountId,
    required String sourceUrl,
  }) async {
    final location = await _location(accountId, sourceUrl);
    final metadata = await _readMetadata(location.metadataFile);
    if (metadata == null ||
        metadata.sourceFingerprint != location.fingerprint ||
        !await location.mediaFile.exists()) {
      await _removeLocation(location);
      return null;
    }
    final actualLength = await location.mediaFile.length();
    if (actualLength != metadata.byteLength ||
        !metadata.expiresAt.isAfter(_now().toUtc())) {
      await _removeLocation(location);
      return null;
    }
    await _writeMetadata(
      location.metadataFile,
      metadata.copyWith(lastAccessed: _now().toUtc()),
    );
    return VoiceCacheEntry(
      file: location.mediaFile,
      byteLength: actualLength,
      wasCached: true,
    );
  }

  @override
  Future<VoiceCacheEntry> prepare({
    required String accountId,
    required String sourceUrl,
    void Function(VoiceCacheProgress progress)? onProgress,
  }) {
    final operationKey = '$accountId\u0000$sourceUrl';
    final current = _inFlight[operationKey];
    if (current != null) return current;

    final generation = _accountGenerations[accountId] ?? 0;
    late final Future<VoiceCacheEntry> operation;
    operation =
        _prepare(
          accountId: accountId,
          sourceUrl: sourceUrl,
          generation: generation,
          onProgress: onProgress,
        ).whenComplete(() {
          if (identical(_inFlight[operationKey], operation)) {
            _inFlight.remove(operationKey);
          }
        });
    _inFlight[operationKey] = operation;
    return operation;
  }

  Future<VoiceCacheEntry> _prepare({
    required String accountId,
    required String sourceUrl,
    required int generation,
    void Function(VoiceCacheProgress progress)? onProgress,
  }) async {
    final cached = await lookup(accountId: accountId, sourceUrl: sourceUrl);
    if (cached != null) {
      onProgress?.call(
        VoiceCacheProgress(
          receivedBytes: cached.byteLength,
          totalBytes: cached.byteLength,
        ),
      );
      return cached;
    }

    final location = await _location(accountId, sourceUrl);
    await location.mediaFile.parent.create(recursive: true);
    final temporary = File('${location.mediaFile.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    IOSink? sink;
    try {
      int receivedBytes;
      int? expectedBytes;
      if (location.uri.scheme == 'firebase-storage') {
        final storagePath = location.uri.path.substring(1);
        final reference = FirebaseStorage.instance.ref().child(storagePath);
        final metadata = await reference.getMetadata();
        _requireCurrentGeneration(accountId, generation);
        expectedBytes = metadata.size;
        if (expectedBytes == null || expectedBytes <= 0) {
          throw const VoiceCacheException(
            VoiceCacheFailureKind.missing,
            'The managed media object is empty or unavailable.',
          );
        }
        if (expectedBytes > maxBytes) {
          throw const VoiceCacheException(
            VoiceCacheFailureKind.transient,
            'This recording is larger than the offline cache limit.',
          );
        }
        final task = reference.writeToFile(temporary);
        final subscription = task.snapshotEvents.listen((snapshot) {
          onProgress?.call(
            VoiceCacheProgress(
              receivedBytes: snapshot.bytesTransferred,
              totalBytes: snapshot.totalBytes,
            ),
          );
        });
        try {
          await task;
        } finally {
          await subscription.cancel();
        }
        receivedBytes = await temporary.length();
      } else {
        final response = await _download(location.uri);
        _requireCurrentGeneration(accountId, generation);
        expectedBytes = response.contentLength;
        sink = temporary.openWrite();
        receivedBytes = 0;
        await for (final chunk in response.bytes) {
          receivedBytes += chunk.length;
          if (receivedBytes > maxBytes) {
            throw const VoiceCacheException(
              VoiceCacheFailureKind.transient,
              'This recording is larger than the offline cache limit.',
            );
          }
          sink.add(chunk);
          onProgress?.call(
            VoiceCacheProgress(
              receivedBytes: receivedBytes,
              totalBytes: expectedBytes,
            ),
          );
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (receivedBytes == 0 ||
          (expectedBytes != null && expectedBytes != receivedBytes)) {
        throw const VoiceCacheException(
          VoiceCacheFailureKind.transient,
          'The recording download was incomplete.',
        );
      }
      _requireCurrentGeneration(accountId, generation);
      await temporary.rename(location.mediaFile.path);
      final now = _now().toUtc();
      await _writeMetadata(
        location.metadataFile,
        _VoiceCacheMetadata(
          sourceFingerprint: location.fingerprint,
          byteLength: receivedBytes,
          lastAccessed: now,
          expiresAt: now.add(expiry),
        ),
      );
      await prune(accountId, protectedFingerprint: location.fingerprint);
      return VoiceCacheEntry(
        file: location.mediaFile,
        byteLength: receivedBytes,
        wasCached: false,
      );
    } catch (error) {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
      if (error is VoiceCacheException) rethrow;
      final kind = classifyVoiceCacheFailure(error, hasCachedFile: false);
      throw VoiceCacheException(kind, _failureMessage(kind), cause: error);
    }
  }

  Future<void> prune(String accountId, {String? protectedFingerprint}) async {
    final root = await _root(accountId);
    if (!await root.exists()) return;
    final entries = <(_VoiceCacheLocation, _VoiceCacheMetadata)>[];
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final metadata = await _readMetadata(entity);
      if (metadata == null) {
        await entity.delete();
        continue;
      }
      final mediaPath = entity.path.substring(0, entity.path.length - 5);
      final mediaFile = File(mediaPath);
      final location = _VoiceCacheLocation(
        uri: Uri(),
        fingerprint: metadata.sourceFingerprint,
        mediaFile: mediaFile,
        metadataFile: entity,
      );
      if (!metadata.expiresAt.isAfter(_now().toUtc()) ||
          !await mediaFile.exists()) {
        await _removeLocation(location);
        continue;
      }
      entries.add((location, metadata));
    }
    entries.sort((a, b) => a.$2.lastAccessed.compareTo(b.$2.lastAccessed));
    var totalBytes = entries.fold<int>(
      0,
      (total, entry) => total + entry.$2.byteLength,
    );
    for (final entry in entries) {
      if (totalBytes <= maxBytes) break;
      if (entry.$1.fingerprint == protectedFingerprint) continue;
      await _removeLocation(entry.$1);
      totalBytes -= entry.$2.byteLength;
    }
  }

  Future<void> clearAllForUser(String accountId) async {
    _accountGenerations[accountId] = (_accountGenerations[accountId] ?? 0) + 1;
    final root = await _root(accountId);
    if (await root.exists()) await root.delete(recursive: true);
  }

  void _requireCurrentGeneration(String accountId, int generation) {
    if ((_accountGenerations[accountId] ?? 0) == generation) return;
    throw const VoiceCacheException(
      VoiceCacheFailureKind.authorization,
      'This account session ended before the download completed.',
    );
  }

  Future<_VoiceCacheLocation> _location(
    String accountId,
    String sourceUrl,
  ) async {
    _validateAccountId(accountId);
    final uri = Uri.tryParse(sourceUrl);
    final extension = uri?.pathSegments.lastOrNull
        ?.split('.')
        .last
        .toLowerCase();
    if (uri == null ||
        !const {'https', 'firebase-storage'}.contains(uri.scheme) ||
        extension == null ||
        !_supportedExtensions.contains(extension)) {
      throw const VoiceCacheException(
        VoiceCacheFailureKind.unsupported,
        'This recording format is not supported.',
      );
    }
    if (uri.scheme == 'firebase-storage' && !_isCanonicalManagedPath(uri)) {
      throw const VoiceCacheException(
        VoiceCacheFailureKind.unsupported,
        'The managed media path is invalid.',
      );
    }
    final fingerprint = _fingerprint(sourceUrl);
    final root = await _root(accountId);
    final mediaFile = File(
      '${root.path}${Platform.pathSeparator}$fingerprint.$extension',
    );
    return _VoiceCacheLocation(
      uri: uri,
      fingerprint: fingerprint,
      mediaFile: mediaFile,
      metadataFile: File('${mediaFile.path}.json'),
    );
  }

  bool _isCanonicalManagedPath(Uri uri) {
    if (uri.host.isNotEmpty || uri.hasQuery || uri.hasFragment) return false;
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return RegExp(
      r'^(users/[A-Za-z0-9_-]{1,160}/profile/[A-Za-z0-9_.-]{1,160}|groups/[A-Za-z0-9_-]{1,160}/covers/[A-Za-z0-9_.-]{1,160}|groups/[A-Za-z0-9_-]{1,160}/messages/[A-Za-z0-9_-]{1,160}/[A-Za-z0-9_.-]{1,160})$',
    ).hasMatch(path);
  }

  Future<Directory> _root(String accountId) async {
    _validateAccountId(accountId);
    if (cacheRootProvider != null) return cacheRootProvider!(accountId);
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}voice-cache'
      '${Platform.pathSeparator}$accountId',
    );
  }

  void _validateAccountId(String accountId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(accountId)) {
      throw ArgumentError('Invalid voice-cache account identifier.');
    }
  }

  Future<_VoiceCacheMetadata?> _readMetadata(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return _VoiceCacheMetadata.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMetadata(File file, _VoiceCacheMetadata metadata) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> _removeLocation(_VoiceCacheLocation location) async {
    if (await location.mediaFile.exists()) await location.mediaFile.delete();
    if (await location.metadataFile.exists()) {
      await location.metadataFile.delete();
    }
  }

  static Future<VoiceDownloadResponse> _downloadWithHttpClient(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw VoiceHttpException(statusCode: response.statusCode);
      }
      return VoiceDownloadResponse(
        contentLength: response.contentLength >= 0
            ? response.contentLength
            : null,
        bytes: _closeClientAfter(response, client),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  static Stream<List<int>> _closeClientAfter(
    Stream<List<int>> bytes,
    HttpClient client,
  ) async* {
    try {
      yield* bytes;
    } finally {
      client.close();
    }
  }

  static String _fingerprint(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _failureMessage(VoiceCacheFailureKind kind) {
    return switch (kind) {
      VoiceCacheFailureKind.unsupported =>
        'This recording format is not supported.',
      VoiceCacheFailureKind.authorization =>
        'You no longer have permission to access this recording.',
      VoiceCacheFailureKind.missing =>
        'This recording has been removed or is no longer available.',
      VoiceCacheFailureKind.offlineMiss =>
        'This recording is not downloaded for offline use.',
      VoiceCacheFailureKind.transient =>
        'The recording could not be downloaded. Try again.',
    };
  }
}

class _VoiceCacheLocation {
  final Uri uri;
  final String fingerprint;
  final File mediaFile;
  final File metadataFile;

  const _VoiceCacheLocation({
    required this.uri,
    required this.fingerprint,
    required this.mediaFile,
    required this.metadataFile,
  });
}

class _VoiceCacheMetadata {
  final String sourceFingerprint;
  final int byteLength;
  final DateTime lastAccessed;
  final DateTime expiresAt;

  const _VoiceCacheMetadata({
    required this.sourceFingerprint,
    required this.byteLength,
    required this.lastAccessed,
    required this.expiresAt,
  });

  factory _VoiceCacheMetadata.fromJson(Map<String, dynamic> json) {
    return _VoiceCacheMetadata(
      sourceFingerprint: json['sourceFingerprint'] as String,
      byteLength: json['byteLength'] as int,
      lastAccessed: DateTime.parse(json['lastAccessed'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    );
  }

  _VoiceCacheMetadata copyWith({DateTime? lastAccessed}) {
    return _VoiceCacheMetadata(
      sourceFingerprint: sourceFingerprint,
      byteLength: byteLength,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'sourceFingerprint': sourceFingerprint,
    'byteLength': byteLength,
    'lastAccessed': lastAccessed.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
}
