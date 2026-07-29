import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/insight_model.dart';
import 'canonical_identity_service.dart';
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
  final CanonicalIdentitySource _identitySource;

  InsightService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    CanonicalIdentitySource? identitySource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _identitySource =
           identitySource ??
           FirestoreCanonicalIdentitySource(
             firestore ?? FirebaseFirestore.instance,
           );

  String _requireUserId() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to continue.');
    return uid;
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
          final models = await Future.wait(
            snapshot.docs.map((pointer) async {
              final insightId =
                  pointer.data()['insightId']?.toString() ?? pointer.id;
              try {
                final insight = await _firestore
                    .collection('insights')
                    .doc(insightId)
                    .get();
                if (!insight.exists) return null;
                final model = InsightModel.fromFirestore(insight);
                if (model.status != 'active' ||
                    !model.expiresAt.isAfter(DateTime.now())) {
                  return null;
                }
                return model;
              } catch (_) {
                return null;
              }
            }),
          );
          return models.whereType<InsightModel>().toList(growable: false);
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
    await _functions.httpsCallable('publishInsight').call({
      'title': insight.title.trim(),
      'body': insight.body.trim(),
      'themeId': insight.themeId,
    });
  }

  @override
  Future<void> deleteInsight(String insightId) async {
    await _firestore.collection('insights').doc(insightId).update({
      'status': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    final identity = await _identitySource.load(uid);
    final reference = _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(comment.id);
    await reference.set({
      'schemaVersion': 2,
      'insightId': insightId,
      'authorUid': uid,
      'authorName': identity.displayName,
      if (identity.photoUrl != null) 'authorPhotoUrl': identity.photoUrl,
      'body': comment.body.trim(),
      if (comment.replyToId?.isNotEmpty == true) 'replyToId': comment.replyToId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await waitForDocumentCommit(reference);
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
    if (!isLiking) {
      await reference.delete();
      await waitForDocumentCommit(reference);
      return;
    }
    await reference.set({
      'uid': userId,
      'reaction': 'helpful',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await waitForDocumentCommit(reference);
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
      'insightId': insight.id,
      'savedAt': FieldValue.serverTimestamp(),
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
        .asyncMap((snapshot) async {
          final insights = await Future.wait(
            snapshot.docs.map((saved) async {
              try {
                final document = await _firestore
                    .collection('insights')
                    .doc(saved.id)
                    .get();
                if (!document.exists) {
                  await saved.reference.delete();
                  return null;
                }
                final insight = InsightModel.fromFirestore(document);
                if (insight.status != 'active' ||
                    !insight.expiresAt.isAfter(DateTime.now())) {
                  await saved.reference.delete();
                  return null;
                }
                return insight;
              } catch (error) {
                if (!shouldRemoveUnavailableSavedInsight(error)) rethrow;
                await saved.reference.delete();
                return null;
              }
            }),
          );
          return insights.whereType<InsightModel>().toList(growable: false);
        });
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
