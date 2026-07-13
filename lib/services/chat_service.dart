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
        .snapshots()
        .map((snapshot) {
      final groups = snapshot.docs.map((doc) => GroupModel.fromFirestore(doc)).toList();
      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return groups;
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

    final docRef = _firestore.collection('groups').doc();
    
    final data = {
      'name': name,
      'members': [user.uid],
      'readingProgress': { user.uid: 0.0 },
      'userCompletedChapters': { user.uid: [] },
      'pinnedScripture': '',
      'description': description,
      'createdAt': Timestamp.now(),
      'groupType': groupType,
      'topic': topic,
      'studyBook': studyBook,
      'totalChapters': totalChapters,
      'startDate': startDate != null ? Timestamp.fromDate(startDate) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
      'extensionCount': 0,
    };

    await docRef.set(data);

    return GroupModel(
      id: docRef.id,
      name: name,
      members: [user.uid],
      readingProgress: { user.uid: 0.0 },
      userCompletedChapters: { user.uid: [] },
      pinnedScripture: '',
      description: description,
      createdAt: DateTime.now(),
      groupType: groupType,
      topic: topic,
      studyBook: studyBook,
      totalChapters: totalChapters,
      startDate: startDate,
      endDate: endDate,
      unreadCounts: {},
      extensionCount: 0,
    );
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

  // Extend group duration (Max 3 times)
  Future<bool> extendGroupDuration(String groupId, Duration extraTime) async {
    final docRef = _firestore.collection('groups').doc(groupId);
    final docSnap = await docRef.get();

    if (!docSnap.exists) throw Exception('Group not found');
    
    final data = docSnap.data() as Map<String, dynamic>;
    int currentExtensions = data['extensionCount'] ?? 0;
    
    if (currentExtensions >= 3) {
      return false; // Cannot extend more than 3 times
    }
    
    Timestamp? currentEndDateTs = data['endDate'];
    DateTime currentEndDate = currentEndDateTs != null ? currentEndDateTs.toDate() : DateTime.now();
    DateTime newEndDate = currentEndDate.add(extraTime);

    await docRef.update({
      'endDate': Timestamp.fromDate(newEndDate),
      'extensionCount': FieldValue.increment(1),
    });
    
    return true;
  }

  // Leave a group
  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final docRef = _firestore.collection('groups').doc(groupId);
    final docSnap = await docRef.get();
    
    if (docSnap.exists) {
      List<String> currentMembers = List<String>.from(docSnap.data()?['members'] ?? []);
      
      // Apply 30-day cooldown between leaving user and all other current members
      await _applyCooldowns(user.uid, currentMembers);
    }

    await docRef.update({
      'members': FieldValue.arrayRemove([user.uid]),
      'readingProgress.${user.uid}': FieldValue.delete(),
      'userCompletedChapters.${user.uid}': FieldValue.delete(),
    });
  }

  // Apply 30-day cooldown to prevent re-grouping
  Future<void> _applyCooldowns(String leavingUserId, List<String> groupMembers) async {
    if (groupMembers.isEmpty) return;
    
    final batch = _firestore.batch();
    final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));
    
    for (String memberId in groupMembers) {
      if (memberId == leavingUserId) continue;
      
      // Create a deterministic ID so either A->B or B->A maps to the same doc
      final ids = [leavingUserId, memberId]..sort();
      final cooldownId = '${ids[0]}_${ids[1]}';
      
      final ref = _firestore.collection('cooldowns').doc(cooldownId);
      batch.set(ref, {
        'users': ids,
        'expiresAt': expiresAt,
      }, SetOptions(merge: true));
    }
    
    await batch.commit();
  }

  // Check if a cooldown exists between current user and target user
  Future<DateTime?> checkCooldown(String targetUserId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final ids = [user.uid, targetUserId]..sort();
    final cooldownId = '${ids[0]}_${ids[1]}';

    try {
      final doc = await _firestore.collection('cooldowns').doc(cooldownId).get();
      if (doc.exists) {
        final expiresAt = doc.data()?['expiresAt'] as Timestamp?;
        if (expiresAt != null) {
          final expirationDate = expiresAt.toDate();
          if (expirationDate.isAfter(DateTime.now())) {
            return expirationDate;
          }
        }
      }
    } catch (e) {
      // Ignored
    }
    return null;
  }

  // Add multiple members to a group
  Future<void> addMembersToGroup(String groupId, List<String> memberIds) async {
    final docRef = _firestore.collection('groups').doc(groupId);
    final docSnap = await docRef.get();

    if (!docSnap.exists) throw Exception('Group not found');

    List<String> currentMembers = List<String>.from(docSnap.data()?['members'] ?? []);
    if (currentMembers.length + memberIds.length > 12) {
      throw Exception('Group cannot exceed 12 members');
    }

    Map<String, dynamic> updates = {
      'members': FieldValue.arrayUnion(memberIds),
    };
    
    for (String uid in memberIds) {
      if (!currentMembers.contains(uid)) {
        updates['readingProgress.$uid'] = 0.0;
        updates['userCompletedChapters.$uid'] = [];
      }
    }

    await docRef.update(updates);
  }

  // Edit a group
  Future<void> editGroup(String groupId, String name, String scripture, {String? description, String? photoUrl}) async {
    Map<String, dynamic> updates = {
      'name': name,
      'pinnedScripture': scripture,
    };
    if (description != null) updates['description'] = description;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    // Fire and forget to allow offline persistence to work instantly
    _firestore.collection('groups').doc(groupId).update(updates);
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
        final groupData = groupDoc.data()!;
        final groupName = groupData['name'] ?? 'Study Group';
        final members = List<String>.from(groupData['members'] ?? []);
        Map<String, dynamic> updates = {
          'lastMessageTime': FieldValue.serverTimestamp(),
        };
        for (String memberId in members) {
          if (memberId != user.uid) {
            updates['unreadCounts.$memberId'] = FieldValue.increment(1);
          }
        }
        await _firestore.collection('groups').doc(groupId).update(updates);

        // Extract a preview text for the notification body
        String notificationBody = 'Sent a message';
        if (parts.isNotEmpty) {
          final firstPart = parts.first;
          if (firstPart.type == 'text' && firstPart.content.isNotEmpty) {
            notificationBody = firstPart.content.length > 50 
              ? '${firstPart.content.substring(0, 50)}...' 
              : firstPart.content;
          } else if (firstPart.type == 'voice') {
            notificationBody = '🎤 Voice note';
          }
        }

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
