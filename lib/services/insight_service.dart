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

  Future<void> createInsight(InsightModel insight) async {
    await _firestore.collection('insights').add(insight.toMap());
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
        .add(comment.toMap());
  }
}
