import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/message_model.dart';

enum ComposerDraftAudience { private, contacts }

/// Stages exposed only as a deterministic test seam for the local draft
/// replacement transaction. A process can stop after any stage; the next
/// load will select the newest valid candidate and restore the canonical file.
enum DraftWriteStage { tempFlushed, backupReady, committed }

typedef DraftWriteHook = Future<void> Function(DraftWriteStage stage);

class ComposerDraft {
  final String title;
  final String body;
  final ComposerDraftAudience audience;

  const ComposerDraft({
    required this.title,
    required this.body,
    required this.audience,
  });

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  @override
  bool operator ==(Object other) {
    return other is ComposerDraft &&
        other.title == title &&
        other.body == body &&
        other.audience == audience;
  }

  @override
  int get hashCode => Object.hash(title, body, audience);
}

class GroupDraft {
  final String text;
  final List<MessagePart> parts;
  final String space;
  final String? replyToMessageId;
  final String? clientMessageId;

  const GroupDraft({
    required this.text,
    required this.parts,
    this.space = 'discussion',
    this.replyToMessageId,
    this.clientMessageId,
  });

  bool get isEmpty => text.trim().isEmpty && parts.isEmpty;
}

class DraftService {
  DraftService({this.draftRootProvider, this.writeHook});

  final Future<Directory> Function(String userId)? draftRootProvider;
  final DraftWriteHook? writeHook;
  final Map<String, Future<void>> _locks = {};

  Future<GroupDraft?> load({
    required String userId,
    required String groupId,
  }) async {
    final file = await _draftFile(userId, groupId);
    return _withLock(_lockKey(file.parent), () async {
      final candidate = await _recoverCandidate<GroupDraft>(
        file,
        decode: _decodeGroupDraft,
      );
      return candidate?.value;
    });
  }

  Future<void> save({
    required String userId,
    required String groupId,
    required GroupDraft draft,
  }) async {
    final file = await _draftFile(userId, groupId);
    await _withLock(_lockKey(file.parent), () async {
      if (draft.isEmpty) {
        await _deleteDraftFiles(file);
        return;
      }
      await _writeJsonAtomically(file, {
        'schemaVersion': 1,
        'text': draft.text,
        'parts': draft.parts.map((part) => part.toMap()).toList(),
        'space': draft.space,
        if (draft.replyToMessageId != null)
          'replyToMessageId': draft.replyToMessageId,
        if (draft.clientMessageId != null)
          'clientMessageId': draft.clientMessageId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> clear({required String userId, required String groupId}) async {
    final file = await _draftFile(userId, groupId);
    await _withLock(_lockKey(file.parent), () => _deleteDraftFiles(file));
  }

  Future<void> clearAllForUser(String userId) async {
    final root = await _draftRoot(userId);
    await _withLock(_lockKey(root), () async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  }

  Future<ComposerDraft?> loadComposerDraft({
    required String userId,
    required ComposerDraftAudience audience,
  }) async {
    final file = await _composerDraftFile(userId, audience);
    return _withLock(_lockKey(file.parent), () async {
      final candidate = await _recoverCandidate<ComposerDraft>(
        file,
        decode: (data) => _decodeComposerDraft(data, audience),
      );
      return candidate?.value;
    });
  }

  Future<void> saveComposerDraft({
    required String userId,
    required ComposerDraft draft,
  }) async {
    final file = await _composerDraftFile(userId, draft.audience);
    await _withLock(_lockKey(file.parent), () async {
      if (draft.isEmpty) {
        await _deleteDraftFiles(file);
        return;
      }
      await _writeJsonAtomically(file, {
        'schemaVersion': 1,
        'title': draft.title,
        'body': draft.body,
        'audience': draft.audience.name,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> clearComposerDraft({
    required String userId,
    required ComposerDraftAudience audience,
  }) async {
    final file = await _composerDraftFile(userId, audience);
    await _withLock(_lockKey(file.parent), () => _deleteDraftFiles(file));
  }

  Future<File> _draftFile(String userId, String groupId) async {
    final safeGroupId = _safeId(groupId);
    final root = await _draftRoot(userId);
    return _scopedFile(root, '$safeGroupId.json');
  }

  Future<Directory> _draftRoot(String userId) async {
    final safeUserId = _safeId(userId);
    late final Directory root;
    if (draftRootProvider != null) {
      root = await draftRootProvider!(safeUserId);
    } else {
      final support = await getApplicationSupportDirectory();
      root = Directory(
        '${support.path}${Platform.pathSeparator}drafts'
        '${Platform.pathSeparator}$safeUserId',
      );
    }
    if (root.path.trim().isEmpty) {
      throw ArgumentError('Invalid local draft root.');
    }
    return Directory(root.absolute.path);
  }

  Future<File> _composerDraftFile(
    String userId,
    ComposerDraftAudience audience,
  ) async {
    final root = await _draftRoot(userId);
    return _scopedFile(root, 'composer-${audience.name}.json');
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, dynamic> data,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await writeHook?.call(DraftWriteStage.tempFlushed);
    await _replaceAtomically(file, temporary);
  }

  Future<void> _replaceAtomically(File file, File temporary) async {
    final backup = File('${file.path}.bak');
    if (await file.exists()) {
      // A previous interrupted replacement may have left a backup. The live
      // file remains intact until it is moved into that backup slot.
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      await writeHook?.call(DraftWriteStage.backupReady);
    }
    try {
      await temporary.rename(file.path);
      await writeHook?.call(DraftWriteStage.committed);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<_DraftCandidate<T>?> _recoverCandidate<T>(
    File file, {
    required T? Function(Map<String, dynamic> data) decode,
  }) async {
    final candidates = <_DraftCandidate<T>>[];
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
        final data = Map<String, dynamic>.from(decoded);
        final value = decode(data);
        if (value == null) continue;
        candidates.add(
          _DraftCandidate<T>(
            file: candidateFile,
            value: value,
            data: data,
            updatedAt: DateTime.tryParse(
              data['updatedAt']?.toString() ?? '',
            )?.toUtc(),
            modifiedAt: await candidateFile.lastModified(),
            priority: files.length - index,
          ),
        );
      } catch (_) {
        // A partially-written candidate is ignored while other valid files
        // remain eligible for recovery.
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((first, second) => _compareCandidates(first, second));
    final selected = candidates.first;
    if (selected.file.path != file.path) {
      await _writeJsonAtomically(file, selected.data);
    }
    for (final stale in files.skip(1)) {
      if (await stale.exists()) await stale.delete();
    }
    return selected;
  }

  int _compareCandidates<T>(_DraftCandidate<T> first, _DraftCandidate<T> second) {
    final firstUpdated = first.updatedAt;
    final secondUpdated = second.updatedAt;
    if (firstUpdated != null || secondUpdated != null) {
      if (firstUpdated == null) return 1;
      if (secondUpdated == null) return -1;
      final logical = secondUpdated.compareTo(firstUpdated);
      if (logical != 0) return logical;
    }
    final modified = second.modifiedAt.compareTo(first.modifiedAt);
    return modified != 0 ? modified : second.priority.compareTo(first.priority);
  }

  GroupDraft? _decodeGroupDraft(Map<String, dynamic> data) {
    final rawParts = data['parts'];
    try {
      return GroupDraft(
        text: data['text']?.toString() ?? '',
        parts: rawParts is List
            ? rawParts
                  .whereType<Map>()
                  .map(
                    (part) =>
                        MessagePart.fromMap(Map<String, dynamic>.from(part)),
                  )
                  .toList(growable: false)
            : const [],
        space: data['space']?.toString() ?? 'discussion',
        replyToMessageId: data['replyToMessageId']?.toString(),
        clientMessageId: data['clientMessageId']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  ComposerDraft? _decodeComposerDraft(
    Map<String, dynamic> data,
    ComposerDraftAudience audience,
  ) {
    final encodedAudience = data['audience'];
    if (encodedAudience is String && encodedAudience != audience.name) {
      return null;
    }
    return ComposerDraft(
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      audience: audience,
    );
  }

  Future<void> _deleteDraftFiles(File file) async {
    for (final candidate in [
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  File _scopedFile(Directory root, String name) {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    final rootPath = _normalizedPath(root.path);
    final parentPath = _normalizedPath(file.parent.path);
    if (parentPath != rootPath) {
      throw ArgumentError('Invalid local draft path.');
    }
    return file;
  }

  String _lockKey(Directory root) => _normalizedPath(root.path);

  String _normalizedPath(String path) {
    final absolute = Directory(path).absolute.path;
    return absolute.replaceFirst(RegExp(r'[\\/]+$'), '');
  }

  Future<T> _withLock<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future<void>.value();
    final completed = Completer<void>();
    final current = previous.then((_) => completed.future);
    _locks[key] = current;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
      if (identical(_locks[key], current)) _locks.remove(key);
    }
  }

  String _safeId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value)) {
      throw ArgumentError('Invalid local draft identifier.');
    }
    return value;
  }
}

class _DraftCandidate<T> {
  final File file;
  final T value;
  final Map<String, dynamic> data;
  final DateTime? updatedAt;
  final DateTime modifiedAt;
  final int priority;

  const _DraftCandidate({
    required this.file,
    required this.value,
    required this.data,
    required this.updatedAt,
    required this.modifiedAt,
    required this.priority,
  });
}

/// Attempts local composer cleanup without turning a successful remote
/// mutation into a false failure. Callers can keep their durable result while
/// deciding how to explain that stale local draft data may remain.
Future<bool> tryClearComposerDraft({
  required DraftService draftService,
  required String userId,
  required ComposerDraftAudience audience,
}) async {
  try {
    await draftService.clearComposerDraft(userId: userId, audience: audience);
    return true;
  } catch (_) {
    return false;
  }
}

/// The group-room equivalent of [tryClearComposerDraft].
Future<bool> tryClearGroupDraft({
  required DraftService draftService,
  required String userId,
  required String groupId,
}) async {
  try {
    await draftService.clear(userId: userId, groupId: groupId);
    return true;
  } catch (_) {
    return false;
  }
}
