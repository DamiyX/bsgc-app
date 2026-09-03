import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/group_model.dart';
import '../models/message_model.dart';
import 'firestore_commit_service.dart';

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

class ChatServiceException implements Exception {
  final String code;
  final String message;

  const ChatServiceException({required this.code, required this.message});

  @override
  String toString() => message;
}

class GroupOperationFailure implements Exception {
  final String code;
  final String message;
  final String? field;

  const GroupOperationFailure({
    required this.code,
    required this.message,
    this.field,
  });

  @override
  String toString() => message;
}

/// Runs a chat-state write and waits for Firestore's server acknowledgement
/// before the caller treats the mutation as durable.
///
/// Firestore resolves writes from its local cache while offline. Keeping the
/// write and acknowledgement as one explicit operation prevents personal room
/// actions from presenting a confirmed result after only a local enqueue.
Future<void> persistAcknowledgedChatStateWrite({
  required Future<void> Function() write,
  required Future<void> Function() awaitAcknowledgement,
}) async {
  await write();
  await awaitAcknowledgement();
}

GroupOperationFailure groupOperationFailureForCode(
  String? code, {
  Object? details,
}) {
  final detailsMap = details is Map ? details : null;
  final field = detailsMap?['field']?.toString();
  if (code == 'invalid-argument' && field == 'dateRange') {
    return GroupOperationFailure(
      code: code!,
      field: field,
      message: StudyDateRangePolicy.messageForReason(
        detailsMap?['reason']?.toString(),
      ),
    );
  }
  return switch (code) {
    'invalid-argument' => const GroupOperationFailure(
        code: 'invalid-argument',
        message: 'Check the study details and try again.',
      ),
    'unauthenticated' => const GroupOperationFailure(
        code: 'unauthenticated',
        message: 'Sign in again to save this study.',
      ),
    'permission-denied' => const GroupOperationFailure(
        code: 'permission-denied',
        message: 'You do not have permission to change this study.',
      ),
    'unavailable' || 'deadline-exceeded' => GroupOperationFailure(
        code: code!,
        message: 'Check your connection and try again.',
      ),
    _ => const GroupOperationFailure(
        code: 'unknown',
        message: 'The study could not be saved right now. Try again.',
      ),
  };
}

class ChapterProgressMutation {
  final List<int> completedChapters;
  final double progress;

  const ChapterProgressMutation({
    required this.completedChapters,
    required this.progress,
  });

  factory ChapterProgressMutation.toggle({
    required Iterable<int> current,
    required int chapter,
    required int totalChapters,
  }) {
    if (totalChapters <= 0 || chapter < 1 || chapter > totalChapters) {
      throw ArgumentError.value(chapter, 'chapter', 'Unknown chapter.');
    }
    final updated =
        current.where((value) => value >= 1 && value <= totalChapters).toSet();
    if (!updated.add(chapter)) updated.remove(chapter);
    final sorted = updated.toList()..sort();
    return ChapterProgressMutation(
      completedChapters: sorted,
      progress: sorted.length / totalChapters,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! ChapterProgressMutation ||
        progress != other.progress ||
        completedChapters.length != other.completedChapters.length) {
      return false;
    }
    for (var index = 0; index < completedChapters.length; index++) {
      if (completedChapters[index] != other.completedChapters[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(progress, Object.hashAll(completedChapters));
}

class GroupStreamRetryController {
  final Stream<List<GroupModel>> Function() _createStream;
  late Stream<List<GroupModel>> stream = _createStream();

  GroupStreamRetryController(this._createStream);

  void retry() {
    stream = _createStream();
  }
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
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
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

  ChatServiceException _callableError(Object error) {
    if (error is FirebaseFunctionsException) {
      return ChatServiceException(
        code: error.code,
        message:
            error.message ?? 'The requested action could not be completed.',
      );
    }
    return const ChatServiceException(
      code: 'unknown',
      message: 'The requested action could not be completed.',
    );
  }

  Stream<List<GroupModel>> getUserGroups() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(const []);

    return _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .where('lifecycle', whereIn: const ['scheduled', 'active'])
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final groups = snapshot.docs.map(GroupModel.fromFirestore).toList();
          groups.sort((a, b) {
            final aTime = a.lastMessageTime ?? a.createdAt;
            final bTime = b.lastMessageTime ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
          return groups;
        });
  }

  Future<GroupPage> getUserGroupPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    Query<Map<String, dynamic>> query = _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .where('lifecycle', whereIn: const ['scheduled', 'active'])
        .orderBy('createdAt', descending: true)
        .limit(boundedPageSize + 1);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    final documents = snapshot.docs.take(boundedPageSize).toList();
    final groups = documents.map(GroupModel.fromFirestore).toList();
    groups.sort((a, b) {
      final aTime = a.lastMessageTime ?? a.createdAt;
      final bTime = b.lastMessageTime ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return GroupPage(
      groups: groups,
      cursor: documents.lastOrNull,
      hasMore: snapshot.docs.length > boundedPageSize,
    );
  }

  static List<GroupModel> sortArchivedGroups(Iterable<GroupModel> source) {
    final groups =
        source.where((group) => group.lifecycle == 'archived').toList();
    groups.sort((a, b) {
      final aTime = a.endDate ?? a.lastMessageTime ?? a.createdAt;
      final bTime = b.endDate ?? b.lastMessageTime ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return groups;
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
        // Calendar keys keep the server date contract independent of the
        // device's UTC offset while the millis values preserve lifecycle
        // scheduling and existing document semantics.
        'startDateKey': startDate == null
            ? null
            : StudyDateRangePolicy.calendarDateKey(startDate),
        'endDateKey': endDate == null
            ? null
            : StudyDateRangePolicy.calendarDateKey(endDate),
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
      throw groupOperationFailureForCode(
        error is FirebaseFunctionsException ? error.code : null,
        details: error is FirebaseFunctionsException ? error.details : null,
      );
    }
  }

  /// Loads archived studies separately so the active study stream stays
  /// bounded to the groups that can receive new activity.
  Future<List<GroupModel>> getArchivedGroups() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return const [];

    final snapshot = await _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .where('lifecycle', isEqualTo: 'archived')
        .orderBy('endDate', descending: true)
        .limit(100)
        .get();
    return sortArchivedGroups(snapshot.docs.map(GroupModel.fromFirestore));
  }

  Future<GroupPage> getArchivedGroupPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    Query<Map<String, dynamic>> query = _firestore
        .collection('groups')
        .where('members', arrayContains: userId)
        .where('lifecycle', isEqualTo: 'archived')
        .orderBy('endDate', descending: true)
        .limit(boundedPageSize + 1);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    final documents = snapshot.docs.take(boundedPageSize).toList();
    return GroupPage(
      groups: sortArchivedGroups(documents.map(GroupModel.fromFirestore)),
      cursor: documents.lastOrNull,
      hasMore: snapshot.docs.length > boundedPageSize,
    );
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
      await _functions.httpsCallable('revokeGroupInvite').call({
        'token': token,
      });
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
      throw groupOperationFailureForCode(
        error is FirebaseFunctionsException ? error.code : null,
        details: error is FirebaseFunctionsException ? error.details : null,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembersProfiles(
    List<String> memberIds,
  ) async {
    if (memberIds.isEmpty) return const [];

    return Future.wait(
      memberIds.map((uid) async {
        try {
          final document =
              await _firestore.collection('users_public').doc(uid).get();
          final data = document.data();
          return {
            'uid': uid,
            'displayName': data?['displayName']?.toString() ?? 'Braid member',
            'photoURL': data?['photoUrl']?.toString() ?? '',
            'profileAvailable': document.exists,
          };
        } catch (_) {
          return {
            'uid': uid,
            'displayName': 'Profile unavailable',
            'photoURL': '',
            'profileAvailable': false,
          };
        }
      }),
    );
  }

  Future<void> updateReadingProgress(String groupId, double progress) async {
    final user = _requireUser();
    final reference = _firestore.collection('groups').doc(groupId);
    await reference.update({
      'readingProgress.${user.uid}': progress.clamp(0, 1),
    });
    await waitForDocumentCommit(reference);
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
        .map(
          (snapshot) => snapshot.docs.map(MessageModel.fromFirestore).toList(),
        );
  }

  GroupMessagePager createMessagePager(
    String groupId, {
    required String space,
    int pageSize = 30,
  }) {
    return GroupMessagePager(
      firestore: _firestore,
      groupId: groupId,
      space: space,
      pageSize: pageSize,
    );
  }

  Stream<MessageVisibilityState> watchMessageVisibility(String groupId) {
    final user = _requireUser();
    final groupStateReference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId);
    final hiddenMessagesReference = groupStateReference.collection(
      'hidden_messages',
    );

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
        groupStateSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
        hiddenMessagesSubscription;
    var hasGroupState = false;
    var hasHiddenMessages = false;
    DateTime? clearedBefore;
    Set<String> hiddenMessageIds = const {};
    late final StreamController<MessageVisibilityState> controller;

    void emitWhenReady() {
      if (!hasGroupState || !hasHiddenMessages || controller.isClosed) return;
      controller.add(
        MessageVisibilityState(
          hiddenMessageIds: hiddenMessageIds,
          clearedBefore: clearedBefore,
        ),
      );
    }

    controller = StreamController<MessageVisibilityState>(
      onListen: () {
        groupStateSubscription = groupStateReference.snapshots().listen((
          snapshot,
        ) {
          final rawClearedBefore = snapshot.data()?['clearedBefore'];
          clearedBefore =
              rawClearedBefore is Timestamp ? rawClearedBefore.toDate() : null;
          hasGroupState = true;
          emitWhenReady();
        }, onError: controller.addError);
        hiddenMessagesSubscription = hiddenMessagesReference.snapshots().listen(
          (snapshot) {
            hiddenMessageIds =
                snapshot.docs.map((document) => document.id).toSet();
            hasHiddenMessages = true;
            emitWhenReady();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await groupStateSubscription?.cancel();
        await hiddenMessagesSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<String> sendHybridMessage(
    String groupId,
    List<MessagePart> parts, {
    String? replyToMessageId,
    String? clientMessageId,
    String space = 'discussion',
  }) async {
    _requireUser();
    if (parts.isEmpty || parts.length > 4) {
      throw ArgumentError('A message must contain between one and four parts.');
    }
    _validateMessageParts(parts);
    final stableId = clientMessageId ?? _uuid.v4();
    if (!const {'reflection', 'discussion', 'prayer'}.contains(space)) {
      throw ArgumentError.value(space, 'space', 'Unknown study space.');
    }
    try {
      final response = await _functions.httpsCallable('sendGroupMessage').call({
        'groupId': groupId,
        'messageId': stableId,
        'clientMessageId': stableId,
        'space': space,
        if (replyToMessageId?.isNotEmpty == true)
          'replyToMessageId': replyToMessageId,
        'parts': parts.map((part) => part.toMap()).toList(),
      });
      final messageId = response.data is Map
          ? (response.data as Map)['messageId']?.toString()
          : null;
      if (messageId != stableId) {
        throw const ChatServiceException(
          code: 'invalid-response',
          message: 'The server did not acknowledge the expected message.',
        );
      }
      return stableId;
    } catch (error) {
      if (error is ChatServiceException) rethrow;
      throw _callableError(error);
    }
  }

  Future<void> resetUnreadCount(String groupId) async {
    final user = _requireUser();
    final reference = _firestore.collection('groups').doc(groupId);
    await persistAcknowledgedChatStateWrite(
      write: () => reference.update({'unreadCounts.${user.uid}': 0}),
      awaitAcknowledgement: () => waitForDocumentCommit(reference),
    );
  }

  Future<void> deleteMessage(String groupId, String messageId) async {
    final response = await _functions.httpsCallable('deleteGroupMessage').call({
      'groupId': groupId,
      'messageId': messageId,
    });
    if (response.data is! Map ||
        (response.data as Map)['messageId']?.toString() != messageId) {
      throw StateError('The server did not acknowledge message removal.');
    }
  }

  Future<void> deleteMessageForMe(String groupId, String messageId) async {
    final user = _requireUser();
    final reference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId)
        .collection('hidden_messages')
        .doc(messageId);
    await persistAcknowledgedChatStateWrite(
      write: () => reference.set({
        'messageId': messageId,
        'hiddenAt': FieldValue.serverTimestamp(),
      }),
      awaitAcknowledgement: () => waitForDocumentCommit(reference),
    );
  }

  Future<void> clearChatForMe(String groupId) async {
    final user = _requireUser();
    final reference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId);
    await persistAcknowledgedChatStateWrite(
      write: () => reference.set({
        'groupId': groupId,
        'clearedBefore': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      awaitAcknowledgement: () => waitForDocumentCommit(reference),
    );
  }

  Future<void> setGroupMuted(String groupId, bool muted) async {
    final user = _requireUser();
    final reference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('group_state')
        .doc(groupId);
    await reference.set({
      'groupId': groupId,
      if (muted)
        'mutedUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 365)),
        )
      else
        'mutedUntil': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Firestore resolves an offline write locally. Do not let the study
    // details switch present a durable preference until the server has
    // acknowledged this account-scoped mutation.
    await waitForDocumentCommit(reference);
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
    final response = await _functions.httpsCallable('editGroupMessage').call({
      'groupId': groupId,
      'messageId': messageId,
      'parts': newParts.map((part) => part.toMap()).toList(),
    });
    if (response.data is! Map ||
        (response.data as Map)['messageId']?.toString() != messageId) {
      throw StateError('The server did not acknowledge message editing.');
    }
  }

  Future<ChapterProgressMutation> toggleGroupStudyChapter(
    String groupId, {
    required int chapter,
    required int totalChapters,
  }) async {
    final user = _requireUser();
    final reference = _firestore.collection('groups').doc(groupId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final rawByUser = snapshot.data()?['userCompletedChapters'];
      final rawCurrent = rawByUser is Map ? rawByUser[user.uid] : null;
      final current = rawCurrent is List
          ? rawCurrent.whereType<num>().map((value) => value.toInt())
          : const <int>[];
      final mutation = ChapterProgressMutation.toggle(
        current: current,
        chapter: chapter,
        totalChapters: totalChapters,
      );
      transaction.update(reference, {
        'readingProgress.${user.uid}': mutation.progress,
        'userCompletedChapters.${user.uid}': mutation.completedChapters,
      });
      return mutation;
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
          if (part.caption != null) {
            throw ArgumentError('Text messages cannot have voice summaries.');
          }
        case MessageType.voice:
          final duration = part.durationSeconds;
          if (duration == null || duration < 1 || duration > 300) {
            throw ArgumentError('Voice reflections must be 1–300 seconds.');
          }
          final caption = part.caption?.trim();
          if (caption != null && caption.length > voiceCaptionMaxLength) {
            throw ArgumentError(
              'Voice summaries must be at most $voiceCaptionMaxLength characters.',
            );
          }
          if (!part.hasCanonicalManagedIdentity) {
            throw ArgumentError(
              'Voice reflections must use a registered managed attachment.',
            );
          }
        case MessageType.image:
          if (part.durationSeconds != null) {
            throw ArgumentError('Images cannot have audio duration.');
          }
          if (part.caption != null) {
            throw ArgumentError('Images cannot have voice summaries.');
          }
          if (!part.hasCanonicalManagedIdentity) {
            throw ArgumentError(
              'Images must use a registered managed attachment.',
            );
          }
        case _:
          throw ArgumentError('This attachment type is not supported.');
      }
    }
  }
}

class GroupPage {
  final List<GroupModel> groups;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const GroupPage({
    required this.groups,
    required this.cursor,
    required this.hasMore,
  });
}

class GroupMessagePageItem {
  final MessageModel message;
  final int sortMillis;

  const GroupMessagePageItem({required this.message, required this.sortMillis});
}

class GroupMessagePage {
  final List<GroupMessagePageItem> items;
  final Object? oldestCursor;
  final bool hasMore;

  const GroupMessagePage({
    required this.items,
    required this.oldestCursor,
    required this.hasMore,
  });
}

abstract interface class GroupMessagePageSource {
  Stream<GroupMessagePage> watchLatest({
    required String groupId,
    required String space,
    required int pageSize,
  });

  Future<GroupMessagePage> loadOlder({
    required String groupId,
    required String space,
    required int pageSize,
    required Object? cursor,
  });
}

class FirestoreGroupMessagePageSource implements GroupMessagePageSource {
  final FirebaseFirestore firestore;

  FirestoreGroupMessagePageSource(this.firestore);

  Query<Map<String, dynamic>> _baseQuery(String groupId, String space) {
    return firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .where('space', isEqualTo: space)
        .orderBy('timestamp', descending: true);
  }

  @override
  Stream<GroupMessagePage> watchLatest({
    required String groupId,
    required String space,
    required int pageSize,
  }) {
    return _baseQuery(groupId, space)
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => GroupMessagePage(
            items: snapshot.docChanges
                .where((change) => change.type != DocumentChangeType.removed)
                .map((change) => _pageItem(change.doc))
                .toList(growable: false),
            oldestCursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
            hasMore: snapshot.docs.length >= pageSize,
          ),
        );
  }

  @override
  Future<GroupMessagePage> loadOlder({
    required String groupId,
    required String space,
    required int pageSize,
    required Object? cursor,
  }) async {
    var query = _baseQuery(groupId, space).limit(pageSize);
    if (cursor != null) {
      if (cursor is! DocumentSnapshot<Map<String, dynamic>>) {
        throw StateError('The message page cursor is invalid.');
      }
      query = query.startAfterDocument(cursor);
    }
    final snapshot = await query.get();
    return GroupMessagePage(
      items: snapshot.docs.map(_pageItem).toList(growable: false),
      oldestCursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length >= pageSize,
    );
  }

  GroupMessagePageItem _pageItem(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final timestamp = data?['timestamp'];
    final clientCreatedAt = data?['clientCreatedAt'];
    return GroupMessagePageItem(
      message: MessageModel.fromFirestore(document),
      sortMillis: timestamp is Timestamp
          ? timestamp.millisecondsSinceEpoch
          : clientCreatedAt is Timestamp
              ? clientCreatedAt.millisecondsSinceEpoch
              : 0,
    );
  }
}

class GroupMessagePager {
  final String groupId;
  final String space;
  final int pageSize;
  final GroupMessagePageSource _pageSource;
  final StreamController<List<MessageModel>> _controller =
      StreamController.broadcast();
  final Map<String, GroupMessagePageItem> _items = {};

  StreamSubscription<GroupMessagePage>? _liveSubscription;
  Object? _oldestCursor;
  bool _started = false;
  bool _loadingOlder = false;
  bool hasMore = true;

  GroupMessagePager({
    required FirebaseFirestore firestore,
    required this.groupId,
    required this.space,
    this.pageSize = 30,
  }) : _pageSource = FirestoreGroupMessagePageSource(firestore) {
    _validateSpace();
  }

  GroupMessagePager.fromSource(
    this._pageSource, {
    required this.groupId,
    required this.space,
    this.pageSize = 30,
  }) {
    _validateSpace();
  }

  void _validateSpace() {
    if (!const {'reflection', 'discussion', 'prayer'}.contains(space)) {
      throw ArgumentError.value(space, 'space', 'Unknown study space.');
    }
  }

  Stream<List<MessageModel>> get stream {
    _start();
    return _controller.stream;
  }

  void _start() {
    if (_started) return;
    _started = true;
    _liveSubscription = _pageSource
        .watchLatest(groupId: groupId, space: space, pageSize: pageSize)
        .listen((page) {
      for (final item in page.items) {
        _items[item.message.id] = item;
      }
      if (_oldestCursor == null || _oldestCursor == page.oldestCursor) {
        _oldestCursor = page.oldestCursor;
        hasMore = page.hasMore;
      } else if (!page.hasMore && _items.length < pageSize) {
        hasMore = false;
      }
      _emit();
    }, onError: _controller.addError);
  }

  Future<void> retry() async {
    await _liveSubscription?.cancel();
    _liveSubscription = null;
    _started = false;
    _oldestCursor = null;
    hasMore = true;
    _start();
  }

  Future<void> loadOlder() async {
    if (_loadingOlder || !hasMore) return;
    _loadingOlder = true;
    try {
      final page = await _pageSource.loadOlder(
        groupId: groupId,
        space: space,
        pageSize: pageSize,
        cursor: _oldestCursor,
      );
      for (final item in page.items) {
        _items[item.message.id] = item;
      }
      _oldestCursor = page.oldestCursor ?? _oldestCursor;
      hasMore = page.hasMore;
      _emit();
    } finally {
      _loadingOlder = false;
    }
  }

  void _emit() {
    final items = _items.values.toList()
      ..sort((first, second) {
        final timestampOrder = second.sortMillis.compareTo(first.sortMillis);
        return timestampOrder != 0
            ? timestampOrder
            : second.message.id.compareTo(first.message.id);
      });
    _controller.add(items.map((item) => item.message).toList(growable: false));
  }

  Future<void> dispose() async {
    await _liveSubscription?.cancel();
    await _controller.close();
  }
}
