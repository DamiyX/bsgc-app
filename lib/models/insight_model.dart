import 'package:cloud_firestore/cloud_firestore.dart';

import 'timestamp_contract.dart';

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
  final bool hasKnownCreatedAt;
  final bool hasKnownUpdatedAt;
  final bool hasKnownExpiresAt;

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
    this.hasKnownCreatedAt = true,
    this.hasKnownUpdatedAt = true,
    this.hasKnownExpiresAt = true,
  });

  factory InsightModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    return InsightModel.fromMap(doc.id, data);
  }

  factory InsightModel.fromMap(String id, Map<String, dynamic> data) {
    final created = resolveFirestoreTimestamp(data['createdAt']);
    final updated = resolveFirestoreTimestamp(data['updatedAt']);
    final expires = resolveFirestoreTimestamp(data['expiresAt']);
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
      createdAt: created.value,
      updatedAt: updated.isKnown ? updated.value : created.value,
      expiresAt: expires.isKnown
          ? expires.value
          : created.value.add(const Duration(days: 3)),
      hasKnownCreatedAt: created.isKnown,
      hasKnownUpdatedAt: updated.isKnown,
      hasKnownExpiresAt: expires.isKnown,
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
  final bool hasKnownCreatedAt;

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
    this.hasKnownCreatedAt = true,
  });

  factory InsightCommentModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    return InsightCommentModel.fromMap(doc.id, data);
  }

  factory InsightCommentModel.fromMap(String id, Map<String, dynamic> data) {
    final created = resolveFirestoreTimestamp(data['createdAt']);
    return InsightCommentModel(
      id: id,
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
      createdAt: created.value,
      hasKnownCreatedAt: created.isKnown,
    );
  }
}
