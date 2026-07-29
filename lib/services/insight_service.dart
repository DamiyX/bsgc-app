import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/insight_model.dart';

class InsightService {
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

  Future<void> addComment(String insightId, InsightCommentModel comment) async {
    final uid = _requireUserId();
    if (comment.authorUid != uid) {
      throw StateError('You can publish only your own comment.');
    }
    await _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(comment.id)
        .set({
          'schemaVersion': 2,
          'insightId': insightId,
          'authorUid': uid,
          'authorName': comment.authorName.trim(),
          if (comment.authorPhotoUrl?.isNotEmpty == true)
            'authorPhotoUrl': comment.authorPhotoUrl,
          'body': comment.body.trim(),
          if (comment.replyToId?.isNotEmpty == true)
            'replyToId': comment.replyToId,
          if (comment.replyToName?.isNotEmpty == true)
            'replyToName': comment.replyToName,
          'createdAt': FieldValue.serverTimestamp(),
        });
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
      return;
    }
    await reference.set({
      'uid': userId,
      'reaction': 'helpful',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveInsight(String userId, InsightModel insight) async {
    if (_requireUserId() != userId) return;
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insight.id)
        .set({
          'insightId': insight.id,
          'savedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> unsaveInsight(String userId, String insightId) async {
    if (_requireUserId() != userId) return;
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insightId)
        .delete();
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
                return document.exists
                    ? InsightModel.fromFirestore(document)
                    : null;
              } catch (_) {
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
