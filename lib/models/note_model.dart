import 'package:cloud_firestore/cloud_firestore.dart';

class NoteModel {
  final String id;
  final int schemaVersion;
  final String authorUid;
  final String title;
  final String body;
  final String themeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteModel({
    required this.id,
    this.schemaVersion = 2,
    required this.authorUid,
    required this.title,
    required this.body,
    required this.themeId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : const <String, dynamic>{};
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    return NoteModel(
      id: doc.id,
      schemaVersion: data['schemaVersion'] is int
          ? data['schemaVersion'] as int
          : 1,
      authorUid: data['authorUid'] is String ? data['authorUid'] as String : '',
      title: data['title'] is String ? data['title'] as String : '',
      body: data['body'] is String ? data['body'] as String : '',
      themeId: data['themeId'] is String
          ? data['themeId'] as String
          : 'theme_0',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.now(),
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
