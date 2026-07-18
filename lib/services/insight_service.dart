import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/insight_model.dart';
import 'auth_service.dart';

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
    try {
      await _firestore.collection('insights').doc(insight.id).set(insight.toMap()).timeout(const Duration(seconds: 2));
      await AuthService().recordInteraction();
    } on TimeoutException {
      // Offline sync fallback
    }
  }

  Future<void> deleteInsight(String insightId) async {
    try {
      await _firestore.collection('insights').doc(insightId).delete().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Offline sync fallback
    }
  }

  Future<void> markAsSeen(String insightId, String userId) async {
    try {
      await _firestore.collection('insights').doc(insightId).update({
      'seenBy': FieldValue.arrayUnion([userId])
    }).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Offline sync fallback
    }
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
    try {
      final batch = _firestore.batch();
      final commentRef = _firestore.collection('insights').doc(insightId).collection('comments').doc(comment.id);
      final insightRef = _firestore.collection('insights').doc(insightId);
      
      batch.set(commentRef, comment.toMap());
      batch.update(insightRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'seenBy': [comment.authorUid],
      });
      
      await batch.commit().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Offline sync fallback
    }
  }

  Future<void> toggleCommentLike(String insightId, String commentId, String userId, bool isLiking) async {
    final docRef = _firestore
        .collection('insights')
        .doc(insightId)
        .collection('comments')
        .doc(commentId);
    
    if (isLiking) {
      final batch = _firestore.batch();
      batch.update(docRef, {
        'likedBy': FieldValue.arrayUnion([userId])
      });
      batch.update(_firestore.collection('insights').doc(insightId), {
        'updatedAt': FieldValue.serverTimestamp(),
        'seenBy': [userId], // Bump and reset unseen so others notice activity
      });
      await batch.commit();
    } else {
      await docRef.update({
        'likedBy': FieldValue.arrayRemove([userId])
      });
    }
  }

  Future<void> toggleInsightLike(String insightId, String userId, bool isLiking) async {
    final docRef = _firestore.collection('insights').doc(insightId);
    if (isLiking) {
      await docRef.update({
        'likedBy': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
        'seenBy': [userId], // Bump and reset unseen so others notice activity
      });
    } else {
      await docRef.update({
        'likedBy': FieldValue.arrayRemove([userId])
      });
    }
  }

  // Saved Insights
  Future<void> saveInsight(String userId, InsightModel insight) async {
    try {
      await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insight.id)
        .set(insight.toMap())
        .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Offline sync fallback
    }
  }

  Future<void> unsaveInsight(String userId, String insightId) async {
    try {
      await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_insights')
        .doc(insightId)
        .delete()
        .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Offline sync fallback
    }
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

  Future<bool> isInsightSaved(String userId, String insightId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('saved_insights')
          .doc(insightId)
          .snapshots()
          .first;
      return snapshot.exists;
    } catch (e) {
      return false;
    }
  }
}
