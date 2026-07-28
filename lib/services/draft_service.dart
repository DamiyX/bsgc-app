import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/message_model.dart';

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
  Future<GroupDraft?> load({
    required String userId,
    required String groupId,
  }) async {
    var file = await _draftFile(userId, groupId);
    if (!await file.exists()) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) return null;
      file = backup;
    }
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final rawParts = data['parts'];
      return GroupDraft(
        text: data['text']?.toString() ?? '',
        parts: rawParts is List
            ? rawParts
                  .whereType<Map>()
                  .map(
                    (part) => MessagePart.fromMap(
                      Map<String, dynamic>.from(part),
                    ),
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

  Future<void> save({
    required String userId,
    required String groupId,
    required GroupDraft draft,
  }) async {
    final file = await _draftFile(userId, groupId);
    if (draft.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }

    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'text': draft.text,
        'parts': draft.parts.map((part) => part.toMap()).toList(),
        'space': draft.space,
        if (draft.replyToMessageId != null)
          'replyToMessageId': draft.replyToMessageId,
        if (draft.clientMessageId != null)
          'clientMessageId': draft.clientMessageId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<void> clear({
    required String userId,
    required String groupId,
  }) async {
    final file = await _draftFile(userId, groupId);
    if (await file.exists()) await file.delete();
  }

  Future<void> clearAllForUser(String userId) async {
    final root = await _draftRoot(userId);
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<File> _draftFile(String userId, String groupId) async {
    final safeGroupId = _safeId(groupId);
    final root = await _draftRoot(userId);
    return File('${root.path}${Platform.pathSeparator}$safeGroupId.json');
  }

  Future<Directory> _draftRoot(String userId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}drafts'
      '${Platform.pathSeparator}${_safeId(userId)}',
    );
  }

  String _safeId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value)) {
      throw ArgumentError('Invalid local draft identifier.');
    }
    return value;
  }
}
