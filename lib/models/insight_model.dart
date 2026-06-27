import 'package:cloud_firestore/cloud_firestore.dart';

class InsightModel {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String title;
  final String body;
  final int themeColor;
  final DateTime createdAt;
  final DateTime expiresAt;

  InsightModel({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.title,
    required this.body,
    required this.themeColor,
    required this.createdAt,
    required this.expiresAt,
  });

  factory InsightModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InsightModel(
      id: doc.id,
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      authorPhotoUrl: data['authorPhotoUrl'],
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      themeColor: data['themeColor'] ?? 0xFF000000,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'title': title,
      'body': body,
      'themeColor': themeColor,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }
}

class InsightCommentModel {
  final String id;
  final String insightId;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String body;
  final DateTime createdAt;

  InsightCommentModel({
    required this.id,
    required this.insightId,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.body,
    required this.createdAt,
  });

  factory InsightCommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InsightCommentModel(
      id: doc.id,
      insightId: data['insightId'] ?? '',
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      authorPhotoUrl: data['authorPhotoUrl'],
      body: data['body'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'insightId': insightId,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'body': body,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
