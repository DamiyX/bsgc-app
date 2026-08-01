import 'package:cloud_firestore/cloud_firestore.dart';

import 'timestamp_contract.dart';

const int noteTitleMaxLength = 160;
const int noteBodyMaxLength = 50000;

String? validateNoteTitle(String? value) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return 'Give this note a short title.';
  if (title.length > noteTitleMaxLength) {
    return 'Use no more than 160 characters.';
  }
  return null;
}

String? validateNoteBody(String? value) {
  final body = value?.trim() ?? '';
  if (body.isEmpty) return 'Write something to save.';
  if (body.length > noteBodyMaxLength) {
    return 'Use no more than 50,000 characters.';
  }
  return null;
}

class NoteModel {
  final String id;
  final int schemaVersion;
  final String authorUid;
  final String title;
  final String body;
  final String themeId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hasKnownCreatedAt;
  final bool hasKnownUpdatedAt;

  NoteModel({
    required this.id,
    this.schemaVersion = 2,
    required this.authorUid,
    required this.title,
    required this.body,
    required this.themeId,
    required this.createdAt,
    required this.updatedAt,
    this.hasKnownCreatedAt = true,
    this.hasKnownUpdatedAt = true,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : const <String, dynamic>{};
    return NoteModel.fromMap(doc.id, data);
  }

  factory NoteModel.fromMap(String id, Map<String, dynamic> data) {
    final created = resolveFirestoreTimestamp(data['createdAt']);
    final updated = resolveFirestoreTimestamp(data['updatedAt']);
    return NoteModel(
      id: id,
      schemaVersion: data['schemaVersion'] is int
          ? data['schemaVersion'] as int
          : 1,
      authorUid: data['authorUid'] is String ? data['authorUid'] as String : '',
      title: data['title'] is String ? data['title'] as String : '',
      body: data['body'] is String ? data['body'] as String : '',
      themeId: data['themeId'] is String
          ? data['themeId'] as String
          : 'theme_0',
      createdAt: created.value,
      updatedAt: updated.isKnown ? updated.value : created.value,
      hasKnownCreatedAt: created.isKnown,
      hasKnownUpdatedAt: updated.isKnown,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorUid': authorUid,
      'schemaVersion': schemaVersion,
      'title': title,
      'body': body,
      'themeId': themeId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
