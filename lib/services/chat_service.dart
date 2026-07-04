import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream of groups the current user is a member of
  Stream<List<GroupModel>> getUserGroups() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value([]);

    return _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => GroupModel.fromFirestore(doc)).toList();
    });
  }

  // Create a new group
  Future<GroupModel> createGroup({
    required String name,
    required String description,
    required String groupType,
    String? topic,
    String? studyBook,
    int totalChapters = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = await _firestore.collection('groups').add({
      'name': name,
      'members': [user.uid],
      'readingProgress': { user.uid: 0.0 },
      'userCompletedChapters': { user.uid: [] },
      'pinnedScripture': '',
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'groupType': groupType,
      'topic': topic,
      'studyBook': studyBook,
      'totalChapters': totalChapters,
      'startDate': startDate != null ? Timestamp.fromDate(startDate) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
    });

    final docSnap = await docRef.get();
    return GroupModel.fromFirestore(docSnap);
  }

  // Join a group by ID
  Future<void> joinGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = _firestore.collection('groups').doc(groupId);
    final docSnap = await docRef.get();

    if (!docSnap.exists) throw Exception('Group not found');

    List<String> currentMembers = List<String>.from(docSnap.data()?['members'] ?? []);
    if (currentMembers.length >= 12) {
      throw Exception('Group is full (max 12 members)');
    }

    if (!currentMembers.contains(user.uid)) {
      await docRef.update({
        'members': FieldValue.arrayUnion([user.uid]),
        'readingProgress.${user.uid}': 0.0,
      });
    }
  }

  // Leave a group
  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([user.uid]),
      'readingProgress.${user.uid}': FieldValue.delete(),
    });
  }

  // Edit a group
  Future<void> editGroup(String groupId, String name, String scripture, {String? description, String? photoUrl}) async {
    Map<String, dynamic> updates = {
      'name': name,
      'pinnedScripture': scripture,
    };
    if (description != null) updates['description'] = description;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    await _firestore.collection('groups').doc(groupId).update(updates);
  }

  // Fetch profiles for a list of user IDs
  Future<List<Map<String, dynamic>>> getGroupMembersProfiles(List<String> memberIds) async {
    if (memberIds.isEmpty) return [];
    
    try {
      // Note: `whereIn` accepts max 10 elements. If a group grows >10, we'll need batching.
      // Since group max is 12, we can just split or fetch individually. Fetching individually is safer for prototypes.
      List<Map<String, dynamic>> profiles = [];
      for (String uid in memberIds) {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          profiles.add(doc.data()!);
        } else {
          // Fallback if profile not found
          profiles.add({
            'uid': uid,
            'displayName': 'Unknown Believer',
            'photoURL': '',
          });
        }
      }
      return profiles;
    } catch (e) {
      return [];
    }
  }

  // Update reading progress for current user in a group
  Future<void> updateReadingProgress(String groupId, double progress) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('groups').doc(groupId).update({
      'readingProgress.${user.uid}': progress,
    });
  }

  // Stream messages for a specific group
  Stream<List<MessageModel>> getGroupMessages(String groupId, {int limit = 20}) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => MessageModel.fromFirestore(doc)).toList();
    });
  }

  // Send a hybrid message
  Future<void> sendHybridMessage(String groupId, List<MessagePart> parts, {String? replyToMessageId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add({
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Believer',
      'senderPhotoUrl': user.photoURL,
      'replyToMessageId': replyToMessageId,
      'parts': parts.map((p) => p.toMap()).toList(),
      'timestamp': FieldValue.serverTimestamp(),
      'starredBy': [],
    });

    // Update group's last message time and increment unread count for other members
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (groupDoc.exists) {
      final members = List<String>.from(groupDoc.data()?['members'] ?? []);
      Map<String, dynamic> updates = {
        'lastMessageTime': FieldValue.serverTimestamp(),
      };
      for (String memberId in members) {
        if (memberId != user.uid) {
          updates['unreadCounts.$memberId'] = FieldValue.increment(1);
        }
      }
      await _firestore.collection('groups').doc(groupId).update(updates);
    }
  }

  // Reset unread count for current user
  Future<void> resetUnreadCount(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('groups').doc(groupId).update({
      'unreadCounts.${user.uid}': 0,
    });
  }

  // Toggle star on a message
  Future<void> toggleStarMessage(String groupId, String messageId, bool isStarred) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);

    if (isStarred) {
      await docRef.update({
        'starredBy': FieldValue.arrayRemove([user.uid])
      });
    } else {
      await docRef.update({
        'starredBy': FieldValue.arrayUnion([user.uid])
      });
    }
  }

  // Delete a message (mark as deleted)
  Future<void> deleteMessage(String groupId, String messageId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'parts': [], // optionally clear the actual content for security
    });
  }

  // Delete a message just for me
  Future<void> deleteMessageForMe(String groupId, String messageId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
      'deletedFor': FieldValue.arrayUnion([user.uid])
    });
  }

  // Clear all messages for me in a group
  Future<void> clearChatForMe(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Fetch all messages
    final querySnapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .get();

    WriteBatch batch = _firestore.batch();
    int count = 0;

    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final deletedFor = List<String>.from(data['deletedFor'] ?? []);
      if (!deletedFor.contains(user.uid)) {
        batch.update(doc.reference, {
          'deletedFor': FieldValue.arrayUnion([user.uid])
        });
        count++;
        // Firestore batches support up to 500 operations
        if (count == 490) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  // Edit a message
  Future<void> editMessage(String groupId, String messageId, List<MessagePart> newParts) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
      'parts': newParts.map((p) => p.toMap()).toList(),
      'isEdited': true,
    });
  }

  // Update study progress and chapters
  Future<void> updateGroupStudyProgress(String groupId, String bookName, int totalChapters, List<int> completedChapters, double progress) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('groups').doc(groupId).update({
      'studyBook': bookName,
      'totalChapters': totalChapters,
      'readingProgress.${user.uid}': progress,
      'userCompletedChapters.${user.uid}': completedChapters,
    });
  }
}
