import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/insight_model.dart';

class InsightService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // For this initial implementation, we'll fetch all insights globally,
  // but only ones that haven't expired (created within the last 3 days).
  // In the future, this can be filtered by contacts or group members.
  Stream<List<InsightModel>> getActiveInsights() {
    return _firestore
        .collection('insights')
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => InsightModel.fromFirestore(doc)).toList();
    });
  }

  Stream<List<InsightModel>> getActiveInsightsForUser(String userId) {
    return _firestore
        .collection('insights')
        .where('authorUid', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      var list = snapshot.docs
          .map((doc) => InsightModel.fromFirestore(doc))
          .where((insight) => insight.expiresAt.isAfter(now))
          .toList();
      list.sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
      return list;
    });
  }

  Future<void> createInsight(InsightModel insight) async {
    await _firestore.collection('insights').doc(insight.id).set(insight.toMap());
  }

  Future<void> deleteInsight(String insightId) async {
    await _firestore.collection('insights').doc(insightId).delete();
  }

  Future<void> markAsSeen(String insightId, String userId) async {
    await _firestore.collection('insights').doc(insightId).update({
      'seenBy': FieldValue.arrayUnion([userId])
    });
  }

  Stream<List<InsightCommentModel>> getComments(String insightId) {
    return _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => InsightCommentModel.fromFirestore(doc)).toList();
    });
  }

  Future<void> addComment(String insightId, InsightCommentModel comment) async {
    await _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(comment.id)
        .set(comment.toMap());
  }

  Future<void> toggleCommentLike(String insightId, String commentId, String userId, bool isLiking) async {
    final docRef = _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(commentId);
    
    if (isLiking) {
      await docRef.update({
        'likedBy': FieldValue.arrayUnion([userId])
      });
    } else {
      await docRef.update({
        'likedBy': FieldValue.arrayRemove([userId])
      });
    }
  }

  // Saved Insights
  Future<void> saveInsight(String userId, InsightModel insight) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insight.id)
        .set(insight.toMap());
  }

  Future<void> unsaveInsight(String userId, String insightId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insightId)
        .delete();
  }

  Stream<List<InsightModel>> getSavedInsights(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => InsightModel.fromFirestore(doc)).toList();
    });
  }
}
