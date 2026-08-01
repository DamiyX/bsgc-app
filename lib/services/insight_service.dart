import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/insight_model.dart';
import 'firestore_commit_service.dart';

bool shouldRemoveUnavailableSavedInsight(Object error) {
  return error is FirebaseException &&
      (error.code == 'permission-denied' || error.code == 'not-found');
}

class InsightCommentCursor {
  final String documentId;
  final int createdAtMicros;

  const InsightCommentCursor({
    required this.documentId,
    required this.createdAtMicros,
  });
}

class InsightCommentPage {
  final List<InsightCommentModel> comments;
  final bool hasMore;
  final InsightCommentCursor? cursor;

  const InsightCommentPage({
    required this.comments,
    required this.hasMore,
    required this.cursor,
  });
}

List<InsightCommentModel> mergeCommentPages(
  Iterable<InsightCommentModel> first,
  Iterable<InsightCommentModel> second,
) {
  final byId = <String, InsightCommentModel>{
    for (final comment in first) comment.id: comment,
    for (final comment in second) comment.id: comment,
  };
  final merged = byId.values.toList();
  merged.sort((a, b) {
    final timeOrder = a.createdAt.compareTo(b.createdAt);
    return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
  });
  return merged;
}

List<InsightCommentModel> commentThreadRoots(
  List<InsightCommentModel> comments,
) {
  final ids = comments.map((comment) => comment.id).toSet();
  return comments
      .where(
        (comment) =>
            comment.replyToId == null || !ids.contains(comment.replyToId),
      )
      .toList(growable: false);
}

abstract interface class MyInsightsDataSource {
  Stream<List<InsightModel>> getActiveInsightsForUser(String userId);
  Future<void> deleteInsight(String insightId);
}

class InsightService implements MyInsightsDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  InsightService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance;

  String _requireUserId() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to continue.');
    return uid;
  }

  bool _hasFeedSnapshot(Map<String, dynamic> data) {
    return data['schemaVersion'] == 2 &&
        data['authorUid'] is String &&
        data['authorName'] is String &&
        data['title'] is String &&
        data['body'] is String &&
        data['themeId'] is String &&
        data['audience'] is String &&
        data['status'] is String &&
        data['createdAt'] is Timestamp &&
        data['updatedAt'] is Timestamp &&
        data['expiresAt'] is Timestamp;
  }

  Future<Map<String, DocumentSnapshot<Map<String, dynamic>>>>
  _loadLegacyInsights(Iterable<String> insightIds) async {
    final ids = insightIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final documents = await Future.wait(
      ids.map((id) => _firestore.collection('insights').doc(id).get()),
    );
    return {
      for (final document in documents)
        if (document.exists) document.id: document,
    };
  }

  Stream<List<InsightModel>> getActiveInsights({int limit = 40}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    final boundedLimit = limit.clamp(1, 50).toInt();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('insight_feed')
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt', descending: true)
        .limit(boundedLimit)
        .snapshots()
        .asyncMap((snapshot) async {
          final legacyIds = snapshot.docs
              .where((pointer) => !_hasFeedSnapshot(pointer.data()))
              .map(
                (pointer) =>
                    pointer.data()['insightId']?.toString() ?? pointer.id,
              );
          final legacyDocuments = await _loadLegacyInsights(legacyIds);
          final now = DateTime.now();
          final models = <InsightModel>[];
          for (final pointer in snapshot.docs) {
            final data = pointer.data();
            try {
              final legacyDocument =
                  legacyDocuments[data['insightId']?.toString() ?? pointer.id];
              final model = _hasFeedSnapshot(data)
                  ? InsightModel.fromMap(pointer.id, data)
                  : legacyDocument == null
                  ? null
                  : InsightModel.fromFirestore(legacyDocument);
              if (model != null &&
                  model.status == 'active' &&
                  model.expiresAt.isAfter(now)) {
                models.add(model);
              }
            } catch (_) {
              // A malformed or legacy pointer should not break the entire feed.
            }
          }
          return models;
        });
  }

  @override
  Stream<List<InsightModel>> getActiveInsightsForUser(
    String userId, {
    int limit = 50,
  }) {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid != userId) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('insights')
        .where('authorUid', isEqualTo: currentUid)
        .where('status', isEqualTo: 'active')
        .orderBy('expiresAt', descending: true)
        .limit(limit.clamp(1, 50).toInt())
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .map(InsightModel.fromFirestore)
              .where(
                (insight) =>
                    insight.status == 'active' &&
                    insight.expiresAt.isAfter(now),
              )
              .toList(growable: false);
        });
  }

  Future<void> createInsight(InsightModel insight) async {
    final uid = _requireUserId();
    if (insight.authorUid != uid) {
      throw StateError('You can publish only your own reflection.');
    }
    final response = await _functions.httpsCallable('publishInsight').call({
      'insightId': insight.id,
      'title': insight.title.trim(),
      'body': insight.body.trim(),
      'themeId': insight.themeId,
    });
    if (response.data is! Map ||
        (response.data as Map)['insightId']?.toString() != insight.id) {
      throw StateError('The server did not acknowledge the expected Insight.');
    }
  }

  @override
  Future<void> deleteInsight(String insightId) async {
    final reference = _firestore.collection('insights').doc(insightId);
    await reference.update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Firestore resolves an offline write locally. Do not let the UI present
    // a durable deletion success until the server has acknowledged it.
    await waitForDocumentCommit(reference);
  }

  Future<void> markAsSeen(String insightId, String userId) async {
    final uid = _requireUserId();
    if (uid != userId) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('insight_state')
        .doc(insightId)
        .set({
          'insightId': insightId,
          'seenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Stream<Set<String>> getSeenInsightIds({int limit = 100}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const {});
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('insight_state')
        .orderBy('updatedAt', descending: true)
        .limit(limit.clamp(1, 100).toInt())
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) => document.id).toSet(),
        );
  }

  Stream<List<InsightCommentModel>> getComments(
    String insightId, {
    int limit = 100,
  }) {
    return _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .orderBy('createdAt')
        .limit(limit.clamp(1, 100).toInt())
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(InsightCommentModel.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<InsightCommentPage> getCommentPage(
    String insightId, {
    InsightCommentCursor? after,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    Query<Map<String, dynamic>> query = _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (after != null) {
      query = query.startAfter([
        Timestamp.fromMicrosecondsSinceEpoch(after.createdAtMicros),
        after.documentId,
      ]);
    }

    final snapshot = await query.limit(boundedPageSize + 1).get();
    final pageDocuments = snapshot.docs.take(boundedPageSize).toList();
    final pageComments = pageDocuments
        .map(InsightCommentModel.fromFirestore)
        .toList(growable: false);
    final commentsWithParents = await _includeMissingCommentParents(
      insightId,
      pageComments,
    );
    final lastDocument = pageDocuments.lastOrNull;
    final lastCreatedAt = lastDocument?.data()['createdAt'];
    return InsightCommentPage(
      comments: mergeCommentPages(commentsWithParents, const []),
      hasMore: snapshot.docs.length > boundedPageSize,
      cursor: lastDocument == null
          ? null
          : InsightCommentCursor(
              documentId: lastDocument.id,
              createdAtMicros: lastCreatedAt is Timestamp
                  ? lastCreatedAt.microsecondsSinceEpoch
                  : 0,
            ),
    );
  }

  Stream<List<InsightCommentModel>> watchNewestComments(
    String insightId, {
    int limit = 50,
  }) {
    final boundedLimit = limit.clamp(1, 100).toInt();
    return _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(boundedLimit)
        .snapshots()
        .asyncMap((snapshot) async {
          final comments = snapshot.docs
              .map(InsightCommentModel.fromFirestore)
              .toList(growable: false);
          return mergeCommentPages(
            await _includeMissingCommentParents(insightId, comments),
            const [],
          );
        });
  }

  Future<int> getCommentCount(String insightId) async {
    final result = await _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .count()
        .get();
    return result.count ?? 0;
  }

  Future<List<InsightCommentModel>> _includeMissingCommentParents(
    String insightId,
    List<InsightCommentModel> comments,
  ) async {
    final byId = {for (final comment in comments) comment.id: comment};
    var missingParentIds = comments
        .map((comment) => comment.replyToId)
        .whereType<String>()
        .where((id) => !byId.containsKey(id))
        .toSet();
    while (missingParentIds.isNotEmpty) {
      final parentSnapshots = await Future.wait(
        missingParentIds.map(
          (parentId) => _firestore
              .collection('insights')
              .doc(insightId)
              .collection('comments')
              .doc(parentId)
              .get(),
        ),
      );
      final foundParents = parentSnapshots
          .where((document) => document.exists)
          .map(InsightCommentModel.fromFirestore)
          .toList(growable: false);
      if (foundParents.isEmpty) break;
      for (final parent in foundParents) {
        byId[parent.id] = parent;
      }
      missingParentIds = foundParents
          .map((comment) => comment.replyToId)
          .whereType<String>()
          .where((id) => !byId.containsKey(id))
          .toSet();
    }
    return byId.values.toList(growable: false);
  }

  Future<void> addComment(String insightId, InsightCommentModel comment) async {
    final uid = _requireUserId();
    if (comment.authorUid != uid) {
      throw StateError('You can publish only your own comment.');
    }
    final response = await _functions
        .httpsCallable('createInsightComment')
        .call({
          'insightId': insightId,
          'commentId': comment.id,
          'body': comment.body.trim(),
          if (comment.replyToId?.isNotEmpty == true)
            'replyToId': comment.replyToId,
        });
    if (response.data is! Map ||
        (response.data as Map)['commentId']?.toString() != comment.id) {
      throw StateError('The server did not acknowledge the expected comment.');
    }
  }

  Future<void> toggleCommentLike(
    String insightId,
    String commentId,
    String userId,
    bool isLiking,
  ) {
    return _toggleReaction(
      _firestore
          .collection('insights')
          .doc(insightId)
          .collection('comments')
          .doc(commentId)
          .collection('reactions')
          .doc(userId),
      userId,
      isLiking,
    );
  }

  Future<void> toggleInsightLike(
    String insightId,
    String userId,
    bool isLiking,
  ) {
    return _toggleReaction(
      _firestore
          .collection('insights')
          .doc(insightId)
          .collection('reactions')
          .doc(userId),
      userId,
      isLiking,
    );
  }

  Future<bool> hasInsightReaction(String insightId) async {
    final uid = _requireUserId();
    final snapshot = await _firestore
        .collection('insights')
        .doc(insightId)
        .collection('reactions')
        .doc(uid)
        .get();
    return snapshot.exists;
  }

  Stream<bool> hasCommentReaction(String insightId, String commentId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(commentId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Future<void> _toggleReaction(
    DocumentReference<Map<String, dynamic>> reference,
    String userId,
    bool isLiking,
  ) async {
    if (_requireUserId() != userId) {
      throw StateError('Reaction identity does not match the signed-in user.');
    }
    final segments = reference.path.split('/');
    final insightId = segments[1];
    final commentId = segments.length > 4 ? segments[3] : null;
    await _functions.httpsCallable('setInsightReaction').call({
      'insightId': insightId,
      'commentId': ?commentId,
      'active': isLiking,
    });
  }

  Future<void> saveInsight(String userId, InsightModel insight) async {
    if (_requireUserId() != userId) return;
    if (insight.status != 'active' ||
        !insight.expiresAt.isAfter(DateTime.now())) {
      throw StateError('Only active Insights can be saved.');
    }
    final reference = _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insight.id);
    await reference.set({
      'schemaVersion': 2,
      'insightId': insight.id,
      'savedAt': FieldValue.serverTimestamp(),
      'snapshotSchemaVersion': 1,
      'authorUid': insight.authorUid,
      'authorName': insight.authorName,
      if (insight.authorPhotoUrl != null)
        'authorPhotoUrl': insight.authorPhotoUrl,
      'title': insight.title,
      'body': insight.body,
      'themeId': insight.themeId,
      'audience': insight.audience,
      'status': insight.status,
      'createdAt': Timestamp.fromDate(insight.createdAt),
      'updatedAt': Timestamp.fromDate(insight.updatedAt),
      'expiresAt': Timestamp.fromDate(insight.expiresAt),
    });
    await waitForDocumentCommit(reference);
  }

  Future<void> unsaveInsight(String userId, String insightId) async {
    if (_requireUserId() != userId) return;
    final reference = _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insightId);
    await reference.delete();
    await waitForDocumentCommit(reference);
  }

  Stream<List<InsightModel>> getSavedInsights(String userId) {
    if (_auth.currentUser?.uid != userId) return Stream.value(const []);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .orderBy('savedAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) => _resolveSavedInsights(snapshot.docs));
  }

  Future<SavedInsightPage> getSavedInsightPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 50,
  }) async {
    if (_auth.currentUser?.uid != userId) {
      return const SavedInsightPage(insights: [], cursor: null, hasMore: false);
    }
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .orderBy('savedAt', descending: true)
        .limit(boundedPageSize + 1);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    final documents = snapshot.docs.take(boundedPageSize).toList();
    return SavedInsightPage(
      insights: await _resolveSavedInsights(documents),
      cursor: documents.lastOrNull,
      hasMore: snapshot.docs.length > boundedPageSize,
    );
  }

  Future<List<InsightModel>> _resolveSavedInsights(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> savedDocuments,
  ) async {
    final documents = savedDocuments.toList(growable: false);
    final legacyIds = documents
        .where((saved) => !_hasFeedSnapshot(saved.data()))
        .map((saved) => saved.id);
    final legacyDocuments = await _loadLegacyInsights(legacyIds);
    final now = DateTime.now();
    final staleReferences = <DocumentReference<Map<String, dynamic>>>[];
    final insights = <InsightModel>[];
    for (final saved in documents) {
      final data = saved.data();
      try {
        final legacyDocument = legacyDocuments[saved.id];
        final insight = _hasFeedSnapshot(data)
            ? InsightModel.fromMap(saved.id, data)
            : legacyDocument == null
            ? null
            : InsightModel.fromFirestore(legacyDocument);
        if (insight == null ||
            insight.status != 'active' ||
            !insight.expiresAt.isAfter(now)) {
          staleReferences.add(saved.reference);
        } else {
          insights.add(insight);
        }
      } catch (error) {
        if (!shouldRemoveUnavailableSavedInsight(error)) rethrow;
        staleReferences.add(saved.reference);
      }
    }
    await Future.wait(staleReferences.map((reference) => reference.delete()));
    return insights;
  }

  Future<bool> isInsightSaved(String userId, String insightId) async {
    if (_auth.currentUser?.uid != userId) return false;
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insightId)
        .get();
    return snapshot.exists;
  }
}

class SavedInsightPage {
  final List<InsightModel> insights;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const SavedInsightPage({
    required this.insights,
    required this.cursor,
    required this.hasMore,
  });
}
