import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SafetyService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  SafetyService({
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

  Future<void> blockUser(String blockedUid) async {
    final uid = _requireUserId();
    if (uid == blockedUid) throw ArgumentError('You cannot block yourself.');
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .doc(blockedUid)
        .set({
          'blockedUid': blockedUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> unblockUser(String blockedUid) async {
    final uid = _requireUserId();
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .doc(blockedUid)
        .delete();
  }

  Stream<List<String>> blockedUserIds() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) => document.id).toList(),
        );
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? groupId,
    String? insightId,
    String? details,
  }) async {
    _requireUserId();
    await _functions.httpsCallable('submitReport').call({
      'targetType': targetType,
      'targetId': targetId,
      if (groupId?.isNotEmpty == true) 'groupId': groupId,
      if (insightId?.isNotEmpty == true) 'insightId': insightId,
      'reason': reason,
      if (details?.trim().isNotEmpty == true) 'details': details!.trim(),
    });
  }
}
