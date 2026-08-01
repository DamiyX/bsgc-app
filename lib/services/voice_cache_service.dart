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

enum VoiceCacheWriteStage {
  afterMediaRename,
  metadataTempFlushed,
  metadataBackupReady,
  metadataCommitted,
}

typedef VoiceCacheWriteHook = Future<void> Function(VoiceCacheWriteStage stage);

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
    this.writeHook,
  }) : _now = now ?? DateTime.now,
       _download = download ?? _downloadWithHttpClient;

  final int maxBytes;
  final Duration expiry;
  final DateTime Function() _now;
  final VoiceCacheRootProvider? cacheRootProvider;
  final VoiceDownload _download;
  final VoiceCacheWriteHook? writeHook;
  final Map<String, Future<VoiceCacheEntry>> _inFlight = {};
  final Map<String, int> _accountGenerations = {};
  final Map<String, Future<void>> _accountFileLocks = {};
  final Set<String> _activeTemporaryPaths = {};
  var _temporarySequence = 0;

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
    return _withAccountFileLock(accountId, () async {
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
    });
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
      _requireCurrentGeneration(accountId, generation);
      onProgress?.call(
        VoiceCacheProgress(
          receivedBytes: cached.byteLength,
          totalBytes: cached.byteLength,
        ),
      );
      return cached;
    }

    _requireCurrentGeneration(accountId, generation);
    final location = await _location(accountId, sourceUrl);
    await location.mediaFile.parent.create(recursive: true);
    final temporary = _temporaryFile(location);
    _activeTemporaryPaths.add(_normalizedPath(temporary.path));
    IOSink? sink;
    var committedMedia = false;
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
      await _withAccountFileLock(accountId, () async {
        // Sign-out increments the generation before waiting on this lock. If
        // it wins the race before the commit begins, abort without moving the
        // downloaded file into the account cache. If the commit already owns
        // the lock, clearAllForUser waits and removes the committed files
        // immediately after this block completes.
        _requireCurrentGeneration(accountId, generation);
        await temporary.rename(location.mediaFile.path);
        committedMedia = true;
        await writeHook?.call(VoiceCacheWriteStage.afterMediaRename);
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
      });
      // A sign-out may have requested a clear while the commit held the
      // account lock. The clear runs immediately after the lock releases;
      // do not report a successful cache entry to the ended session.
      _requireCurrentGeneration(accountId, generation);
      await prune(accountId, protectedFingerprint: location.fingerprint);
      _requireCurrentGeneration(accountId, generation);
      return VoiceCacheEntry(
        file: location.mediaFile,
        byteLength: receivedBytes,
        wasCached: false,
      );
    } catch (error) {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
      // A canceled operation may finish after a newer post-clear operation
      // has committed the same source fingerprint. Only tear down the final
      // cache location when this operation actually moved its own media into
      // place; otherwise deleting it would erase the replacement's result.
      if (committedMedia) {
        await _withAccountFileLock(accountId, () async {
          // A clear or account switch may have handed this fingerprint to a
          // newer session. In that case the newer session owns the location;
          // only the generation that committed this media may clean it up.
          if ((_accountGenerations[accountId] ?? 0) != generation) return;
          await _removeLocation(location, includeMedia: true);
        });
      }
      if (error is VoiceCacheException) rethrow;
      final kind = classifyVoiceCacheFailure(error, hasCachedFile: false);
      throw VoiceCacheException(kind, _failureMessage(kind), cause: error);
    } finally {
      _activeTemporaryPaths.remove(_normalizedPath(temporary.path));
    }
  }

  Future<void> prune(String accountId, {String? protectedFingerprint}) async {
    await _withAccountFileLock(
      accountId,
      () =>
          _pruneUnlocked(accountId, protectedFingerprint: protectedFingerprint),
    );
  }

  Future<void> _pruneUnlocked(
    String accountId, {
    String? protectedFingerprint,
  }) async {
    final root = await _root(accountId);
    if (!await root.exists()) return;
    final metadataFiles = <String>{};
    final temporaryFiles = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.json')) {
        metadataFiles.add(entity.path);
      } else if (entity.path.endsWith('.json.tmp') ||
          entity.path.endsWith('.json.bak')) {
        metadataFiles.add(
          entity.path.substring(0, entity.path.length - 4),
        );
      } else if (entity.path.endsWith('.tmp')) {
        temporaryFiles.add(entity);
      }
    }
    for (final metadataPath in metadataFiles) {
      await _readMetadata(File(metadataPath));
    }
    for (final temporary in temporaryFiles) {
      if (!_activeTemporaryPaths.contains(_normalizedPath(temporary.path)) &&
          await temporary.exists()) {
        await temporary.delete();
      }
    }
    final entries = <(_VoiceCacheLocation, _VoiceCacheMetadata)>[];
    await for (final entity in root.list(followLinks: false)) {
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
    _validateAccountId(accountId);
    _accountGenerations[accountId] = (_accountGenerations[accountId] ?? 0) + 1;
    final prefix = '$accountId\u0000';
    for (final key in _inFlight.keys
        .where((key) => key.startsWith(prefix))
        .toList()) {
      _inFlight.remove(key);
    }
    await _withAccountFileLock(accountId, () async {
      final root = await _root(accountId);
      if (await root.exists()) await root.delete(recursive: true);
    });
  }

  /// Serializes only the short filesystem commit/cleanup sections for one
  /// account. Downloads for other accounts remain independent, and a clear
  /// never waits for an in-flight network transfer that has not reached this
  /// section yet.
  Future<T> _withAccountFileLock<T>(
    String accountId,
    Future<T> Function() action,
  ) async {
    final previous = _accountFileLocks[accountId] ?? Future<void>.value();
    final completed = Completer<void>();
    final current = previous.then((_) => completed.future);
    _accountFileLocks[accountId] = current;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
      if (identical(_accountFileLocks[accountId], current)) {
        _accountFileLocks.remove(accountId);
      }
    }
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

  File _temporaryFile(_VoiceCacheLocation location) {
    final sequence = _temporarySequence++;
    return File(
      '${location.mediaFile.path}.${_now().microsecondsSinceEpoch}-$sequence.tmp',
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

  String _normalizedPath(String path) {
    final absolute = File(path).absolute.path;
    return absolute.replaceFirst(RegExp(r'[\\/]+$'), '');
  }

  Future<_VoiceCacheMetadata?> _readMetadata(File file) async {
    final candidates = <_VoiceMetadataCandidate>[];
    final files = <File>[
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ];
    for (var index = 0; index < files.length; index++) {
      final candidateFile = files[index];
      if (!await candidateFile.exists()) continue;
      try {
        final decoded = jsonDecode(await candidateFile.readAsString());
        if (decoded is! Map) continue;
        final metadata = _VoiceCacheMetadata.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        candidates.add(
          _VoiceMetadataCandidate(
            file: candidateFile,
            metadata: metadata,
            modifiedAt: await candidateFile.lastModified(),
            priority: files.length - index,
          ),
        );
      } catch (_) {
        // A torn metadata write is ignored while another valid candidate can
        // still restore the cache entry.
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((first, second) {
      final logical = second.metadata.lastAccessed.compareTo(
        first.metadata.lastAccessed,
      );
      if (logical != 0) return logical;
      final modified = second.modifiedAt.compareTo(first.modifiedAt);
      return modified != 0
          ? modified
          : second.priority.compareTo(first.priority);
    });
    final selected = candidates.first;
    if (selected.file.path != file.path) {
      // Restore through the same backup-preserving transaction. Hooks are
      // skipped while recovering so a torn write cannot prevent cleanup.
      await _writeMetadata(file, selected.metadata, invokeHook: false);
    }
    for (final stale in files.skip(1)) {
      if (await stale.exists()) await stale.delete();
    }
    return selected.metadata;
  }

  Future<void> _writeMetadata(
    File file,
    _VoiceCacheMetadata metadata, {
    bool invokeHook = true,
  }) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
    if (invokeHook) {
      await writeHook?.call(VoiceCacheWriteStage.metadataTempFlushed);
    }
    final backup = File('${file.path}.bak');
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      if (invokeHook) {
        await writeHook?.call(VoiceCacheWriteStage.metadataBackupReady);
      }
    }
    try {
      await temporary.rename(file.path);
      if (invokeHook) {
        await writeHook?.call(VoiceCacheWriteStage.metadataCommitted);
      }
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<void> _removeLocation(
    _VoiceCacheLocation location, {
    bool includeMedia = true,
  }) async {
    if (includeMedia && await location.mediaFile.exists()) {
      await location.mediaFile.delete();
    }
    for (final candidate in [
      location.metadataFile,
      File('${location.metadataFile.path}.tmp'),
      File('${location.metadataFile.path}.bak'),
    ]) {
      if (await candidate.exists()) await candidate.delete();
    }
    final prefix = '${location.mediaFile.path}.';
    if (await location.mediaFile.parent.exists()) {
      await for (final entity in location.mediaFile.parent.list(
        followLinks: false,
      )) {
        if (entity is! File ||
            !entity.path.startsWith(prefix) ||
            !entity.path.endsWith('.tmp') ||
            _activeTemporaryPaths.contains(_normalizedPath(entity.path))) {
          continue;
        }
        await entity.delete();
      }
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

class _VoiceMetadataCandidate {
  final File file;
  final _VoiceCacheMetadata metadata;
  final DateTime modifiedAt;
  final int priority;

  const _VoiceMetadataCandidate({
    required this.file,
    required this.metadata,
    required this.modifiedAt,
    required this.priority,
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
