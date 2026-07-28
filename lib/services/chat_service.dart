import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/group_model.dart';
import '../models/message_model.dart';

class GroupInvite {
  final String token;
  final String joinUrl;
  final DateTime expiresAt;

  const GroupInvite({
    required this.token,
    required this.joinUrl,
    required this.expiresAt,
  });
}

class InviteRedemption {
  final String groupId;
  final bool joined;
  final bool alreadyMember;

  const InviteRedemption({
    required this.groupId,
    required this.joined,
    required this.alreadyMember,
  });
}

class ChatService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final Uuid _uuid;

  ChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    Uuid? uuid,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _uuid = uuid ?? const Uuid();

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in to continue.');
    }
    return user;
  }

  String createClientMessageId() => _uuid.v4();

  Exception _callableError(Object error) {
    if (error is FirebaseFunctionsException) {
      return Exception(error.message ?? 'The requested action could not be completed.');
    }
    return Exception('The requested action could not be completed.');
  }

  Stream<List<GroupModel>> getUserGroups() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(const []);

    return _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final groups = snapshot.docs
              .map(GroupModel.fromFirestore)
              .where((group) => group.lifecycle != 'archived')
              .toList();
          groups.sort((a, b) {
            final aTime = a.lastMessageTime ?? a.createdAt;
            final bTime = b.lastMessageTime ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
          return groups;
        });
  }

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
    _requireUser();
    try {
      final result = await _functions.httpsCallable('createStudyGroup').call({
        'name': name,
        'description': description,
        'groupType': groupType,
        'topic': topic,
        'studyBook': studyBook,
        'totalChapters': totalChapters,
        'startDateMillis': startDate?.millisecondsSinceEpoch,
        'endDateMillis': endDate?.millisecondsSinceEpoch,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final groupId = data['groupId']?.toString();
      if (groupId == null || groupId.isEmpty) {
        throw const FormatException('Group creation returned no group ID.');
      }

      final snapshot = await _firestore.collection('groups').doc(groupId).get();
      if (!snapshot.exists) {
        throw StateError('The group was created but could not be loaded.');
      }
      return GroupModel.fromFirestore(snapshot);
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<GroupInvite> createGroupInvite(
    String groupId, {
    int expiresInHours = 72,
    int maxUses = 1,
  }) async {
    _requireUser();
    try {
      final result = await _functions.httpsCallable('createGroupInvite').call({
        'groupId': groupId,
        'expiresInHours': expiresInHours,
        'maxUses': maxUses,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return GroupInvite(
        token: data['token'] as String,
        joinUrl: data['joinUrl'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (data['expiresAtMillis'] as num).toInt(),
        ),
      );
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<InviteRedemption> redeemGroupInvite(String token) async {
    _requireUser();
    try {
      final result = await _functions.httpsCallable('redeemGroupInvite').call({
        'token': token,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return InviteRedemption(
        groupId: data['groupId'] as String,
        joined: data['joined'] == true,
        alreadyMember: data['alreadyMember'] == true,
      );
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> revokeGroupInvite(String token) async {
    _requireUser();
    try {
      await _functions.httpsCallable('revokeGroupInvite').call({'token': token});
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<bool> extendGroupDuration(String groupId, Duration extraTime) async {
    _requireUser();
    final days = extraTime.inDays;
    try {
      await _functions.httpsCallable('extendGroupDuration').call({
        'groupId': groupId,
        'days': days,
      });
      return true;
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> leaveGroup(String groupId) async {
    _requireUser();
    try {
      await _functions.httpsCallable('leaveGroup').call({'groupId': groupId});
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> archiveGroup(String groupId) async {
    _requireUser();
    try {
      await _functions.httpsCallable('archiveStudyGroup').call({
        'groupId': groupId,
      });
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> transferGroupOwnership(
    String groupId,
    String newOwnerUid,
  ) async {
    _requireUser();
    try {
      await _functions.httpsCallable('transferGroupOwnership').call({
        'groupId': groupId,
        'newOwnerUid': newOwnerUid,
      });
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> removeGroupMember(String groupId, String memberUid) async {
    _requireUser();
    try {
      await _functions.httpsCallable('removeGroupMember').call({
        'groupId': groupId,
        'memberUid': memberUid,
      });
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<void> editGroup(
    String groupId,
    String name,
    String scripture, {
    String? description,
    String? photoUrl,
  }) async {
    _requireUser();
    try {
      await _functions.httpsCallable('updateStudyGroup').call({
        'groupId': groupId,
        'name': name.trim(),
        'pinnedScripture': scripture.trim(),
        'description': description?.trim() ?? '',
        if (photoUrl != null) 'photoUrl': photoUrl,
      });
    } catch (error) {
      throw _callableError(error);
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembersProfiles(
    List<String> memberIds,
  ) async {
    if (memberIds.isEmpty) return const [];

    final documents = await Future.wait(
      memberIds.map(
        (uid) => _firestore.collection('users_public').doc(uid).get(),
      ),
    );
    return List.generate(memberIds.length, (index) {
      final data = documents[index].data();
      return {
        'uid': memberIds[index],
        'displayName': data?['displayName']?.toString() ?? 'Believer',
        'photoURL': data?['photoUrl']?.toString() ?? '',
      };
    });
  }

  Future<void> updateReadingProgress(String groupId, double progress) async {
    final user = _requireUser();
    await _firestore.collection('groups').doc(groupId).update({
      'readingProgress.${user.uid}': progress.clamp(0, 1),
    });
  }

  Stream<List<MessageModel>> getGroupMessages(
    String groupId, {
    int limit = 30,
  }) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit.clamp(1, 100).toInt())
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(MessageModel.fromFirestore)
            .toList());
  }

  GroupMessagePager createMessagePager(
    String groupId, {
    int pageSize = 30,
  }) {
    return GroupMessagePager(
      firestore: _firestore,
      groupId: groupId,
      pageSize: pageSize,
    );
  }

  Future<String> sendHybridMessage(
    String groupId,
    List<MessagePart> parts, {
    String? replyToMessageId,
    String? clientMessageId,
    String space = 'discussion',
  }) async {
    final user = _requireUser();
    if (parts.isEmpty || parts.length > 4) {
      throw ArgumentError('A message must contain between one and four parts.');
    }
    _validateMessageParts(parts);

    final stableId = clientMessageId ?? _uuid.v4();
    if (!const {'reflection', 'discussion', 'prayer'}.contains(space)) {
      throw ArgumentError.value(space, 'space', 'Unknown study space.');
    }
    final messageRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(stableId);
    await messageRef.set({
      'schemaVersion': 2,
      'clientMessageId': stableId,
      'space': space,
      'senderId': user.uid,
      'senderName': (user.displayName ?? 'Believer').trim(),
      if (user.photoURL?.isNotEmpty == true) 'senderPhotoUrl': user.photoURL,
      if (replyToMessageId?.isNotEmpty == true)
        'replyToMessageId': replyToMessageId,
      'parts': parts.map((part) => part.toMap()).toList(),
      'timestamp': FieldValue.serverTimestamp(),
      'isEdited': false,
      'isDeleted': false,
    });
    return stableId;
  }

  Future<void> resetUnreadCount(String groupId) async {
    final user = _requireUser();
    await _firestore.collection('groups').doc(groupId).update({
      'unreadCounts.${user.uid}': 0,
    });
  }

  Future<void> toggleStarMessage(
    String groupId,
    String messageId,
    bool isStarred,
  ) async {
    final user = _requireUser();
    final reference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .collection('starred_messages')
        .doc(messageId);
    if (isStarred) {
      await reference.delete();
    } else {
      await reference.set({
        'messageId': messageId,
        'starredAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> deleteMessage(String groupId, String messageId) async {
    final reference = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);
    await reference.update({
      'isDeleted': true,
      'parts': <Map<String, dynamic>>[],
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessageForMe(String groupId, String messageId) async {
    final user = _requireUser();
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .collection('hidden_messages')
        .doc(messageId)
        .set({
          'messageId': messageId,
          'hiddenAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> clearChatForMe(String groupId) async {
    final user = _requireUser();
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .set({
          'groupId': groupId,
          'clearedBefore': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> setGroupMuted(String groupId, bool muted) async {
    final user = _requireUser();
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .set({
          'groupId': groupId,
          if (muted)
            'mutedUntil': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 365)),
            )
          else
            'mutedUntil': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<bool> isGroupMuted(String groupId) async {
    final user = _requireUser();
    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .get();
    final mutedUntil = snapshot.data()?['mutedUntil'];
    return mutedUntil is Timestamp &&
        mutedUntil.toDate().isAfter(DateTime.now());
  }

  Future<void> editMessage(
    String groupId,
    String messageId,
    List<MessagePart> newParts,
  ) async {
    if (newParts.isEmpty || newParts.length > 4) {
      throw ArgumentError('A message must contain between one and four parts.');
    }
    _validateMessageParts(newParts);
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
          'parts': newParts.map((part) => part.toMap()).toList(),
          'isEdited': true,
          'editedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> updateGroupStudyProgress(
    String groupId,
    String bookName,
    int totalChapters,
    List<int> completedChapters,
    double progress,
  ) async {
    final user = _requireUser();
    await _firestore.collection('groups').doc(groupId).update({
          'readingProgress.${user.uid}': progress.clamp(0, 1),
      'userCompletedChapters.${user.uid}': completedChapters,
    });
  }

  void _validateMessageParts(List<MessagePart> parts) {
    for (final part in parts) {
      final content = part.content.trim();
      if (content.isEmpty || content.length > 8000) {
        throw ArgumentError('Message content must contain 1–8,000 characters.');
      }
      switch (part.type) {
        case MessageType.text:
          if (part.durationSeconds != null) {
            throw ArgumentError('Text messages cannot have audio duration.');
          }
        case MessageType.voice:
          final duration = part.durationSeconds;
          if (duration == null || duration < 1 || duration > 300) {
            throw ArgumentError('Voice reflections must be 1–300 seconds.');
          }
          _requireSecureMediaUri(content);
        case MessageType.image:
          if (part.durationSeconds != null) {
            throw ArgumentError('Images cannot have audio duration.');
          }
          _requireSecureMediaUri(content);
        case _:
          throw ArgumentError('This attachment type is not supported.');
      }
    }
  }

  void _requireSecureMediaUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw ArgumentError('Message media must use a secure HTTPS URL.');
    }
  }
}

class GroupMessagePager {
  final FirebaseFirestore firestore;
  final String groupId;
  final int pageSize;
  final StreamController<List<MessageModel>> _controller =
      StreamController.broadcast();
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> _documents =
      {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSubscription;
  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestCursor;
  bool _started = false;
  bool _loadingOlder = false;
  bool hasMore = true;

  GroupMessagePager({
    required this.firestore,
    required this.groupId,
    this.pageSize = 30,
  });

  Stream<List<MessageModel>> get stream {
    _start();
    return _controller.stream;
  }

  Query<Map<String, dynamic>> get _baseQuery => firestore
      .collection('groups')
      .doc(groupId)
      .collection('messages')
      .orderBy('timestamp', descending: true);

  void _start() {
    if (_started) return;
    _started = true;
    _liveSubscription = _baseQuery
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.removed) {
                _documents[change.doc.id] = change.doc;
              }
            }
            if (snapshot.docs.isNotEmpty) {
              _oldestCursor ??= snapshot.docs.last;
            }
            if (snapshot.docs.length < pageSize) hasMore = false;
            _emit();
          },
          onError: _controller.addError,
        );
  }

  Future<void> loadOlder() async {
    if (_loadingOlder || !hasMore) return;
    _loadingOlder = true;
    try {
      var query = _baseQuery.limit(pageSize);
      final cursor = _oldestCursor;
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snapshot = await query.get();
      for (final document in snapshot.docs) {
        _documents[document.id] = document;
      }
      if (snapshot.docs.isNotEmpty) _oldestCursor = snapshot.docs.last;
      if (snapshot.docs.length < pageSize) hasMore = false;
      _emit();
    } finally {
      _loadingOlder = false;
    }
  }

  void _emit() {
    final documents = _documents.values.toList()
      ..sort((first, second) {
        final firstTimestamp = first.data()['timestamp'];
        final secondTimestamp = second.data()['timestamp'];
        final firstMillis = firstTimestamp is Timestamp
            ? firstTimestamp.millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch;
        final secondMillis = secondTimestamp is Timestamp
            ? secondTimestamp.millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch;
        return secondMillis.compareTo(firstMillis);
      });
    _controller.add(
      documents.map(MessageModel.fromFirestore).toList(growable: false),
    );
  }

  Future<void> dispose() async {
    await _liveSubscription?.cancel();
    await _controller.close();
  }
}
