import 'package:cloud_firestore/cloud_firestore.dart';

class InsightModel {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String title;
  final String body;
  final String themeId;
  final List<String> seenBy;
  final List<String> likedBy; // Add likedBy field
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;

  InsightModel({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.title,
    required this.body,
    required this.themeId,
    this.seenBy = const [],
    this.likedBy = const [], // Default to empty
    required this.createdAt,
    required this.updatedAt,
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
      themeId: data['themeId'] ?? (data['themeColor'] != null ? data['themeColor'].toString() : 'theme_0'),
      seenBy: List<String>.from(data['seenBy'] ?? []),
      likedBy: List<String>.from(data['likedBy'] ?? []), // Parse likedBy
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : (data['createdAt'] as Timestamp).toDate(),
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
      'themeId': themeId,
      'seenBy': seenBy,
      'likedBy': likedBy, // Serialize likedBy
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
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
  final String? replyToId; // For threaded comments
  final String? replyToName; // To display "Replying to User" without lookup
  final List<String> likedBy; // Users who liked this comment
  final DateTime createdAt;

  InsightCommentModel({
    required this.id,
    required this.insightId,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.body,
    this.replyToId,
    this.replyToName,
    this.likedBy = const [],
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
      replyToId: data['replyToId'],
      replyToName: data['replyToName'],
      likedBy: List<String>.from(data['likedBy'] ?? []),
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
      'replyToId': replyToId,
      'replyToName': replyToName,
      'likedBy': likedBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
