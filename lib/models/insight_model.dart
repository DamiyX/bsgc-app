import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _dateFrom(dynamic value, {DateTime? fallback}) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

class InsightModel {
  final String id;
  final int schemaVersion;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String title;
  final String body;
  final String themeId;
  final String audience;
  final String status;
  final List<String> seenBy;
  final List<String> likedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;

  const InsightModel({
    required this.id,
    this.schemaVersion = 2,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.title,
    required this.body,
    required this.themeId,
    this.audience = 'contacts',
    this.status = 'active',
    this.seenBy = const [],
    this.likedBy = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  factory InsightModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    return InsightModel.fromMap(doc.id, data);
  }

  factory InsightModel.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = _dateFrom(data['createdAt'], fallback: DateTime.now());
    return InsightModel(
      id: id,
      schemaVersion: data['schemaVersion'] is int
          ? data['schemaVersion'] as int
          : 1,
      authorUid: data['authorUid']?.toString() ?? '',
      authorName: data['authorName']?.toString().trim().isNotEmpty == true
          ? data['authorName'].toString()
          : 'Believer',
      authorPhotoUrl: data['authorPhotoUrl']?.toString(),
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      themeId:
          data['themeId']?.toString() ??
          data['themeColor']?.toString() ??
          'theme_0',
      audience: data['audience']?.toString() ?? 'contacts',
      status: data['status']?.toString() ?? 'active',
      // Read-only migration compatibility. New reactions/seen state are stored
      // in per-user documents instead of growing arrays.
      seenBy: _stringList(data['seenBy']),
      likedBy: _stringList(data['likedBy']),
      createdAt: createdAt,
      updatedAt: _dateFrom(data['updatedAt'], fallback: createdAt),
      expiresAt: _dateFrom(
        data['expiresAt'],
        fallback: createdAt.add(const Duration(days: 3)),
      ),
    );
  }
}

class InsightCommentModel {
  final String id;
  final int schemaVersion;
  final String insightId;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String body;
  final String? replyToId;
  final String? replyToName;
  final List<String> likedBy;
  final DateTime createdAt;

  const InsightCommentModel({
    required this.id,
    this.schemaVersion = 2,
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
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    return InsightCommentModel(
      id: doc.id,
      schemaVersion: data['schemaVersion'] is int
          ? data['schemaVersion'] as int
          : 1,
      insightId: data['insightId']?.toString() ?? '',
      authorUid: data['authorUid']?.toString() ?? '',
      authorName: data['authorName']?.toString().trim().isNotEmpty == true
          ? data['authorName'].toString()
          : 'Believer',
      authorPhotoUrl: data['authorPhotoUrl']?.toString(),
      body: data['body']?.toString() ?? '',
      replyToId: data['replyToId']?.toString(),
      replyToName: data['replyToName']?.toString(),
      likedBy: _stringList(data['likedBy']),
      createdAt: _dateFrom(data['createdAt'], fallback: DateTime.now()),
    );
  }
}
