import 'package:cloud_firestore/cloud_firestore.dart';

class NoteModel {
  final String id;
  final String authorUid;
  final String title;
  final String body;
  final String themeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteModel({
    required this.id,
    required this.authorUid,
    required this.title,
    required this.body,
    required this.themeId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NoteModel(
      id: doc.id,
      authorUid: data['authorUid'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      themeId: data['themeId'] ?? 'theme_0',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorUid': authorUid,
      'title': title,
      'body': body,
      'themeId': themeId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
