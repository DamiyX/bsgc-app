import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';

class StudyRoomController extends ChangeNotifier {
  static const messageSpaces = {'reflection', 'discussion', 'prayer'};

  final String groupId;
  final FirebaseFirestore firestore;
  final ChatService chatService;

  final Map<String, GroupMessagePager> _pagers = {};
  final Map<String, StreamSubscription<List<MessageModel>>>
  _messageSubscriptions = {};
  final Map<String, List<MessageModel>> _messagesBySpace = {
    for (final space in messageSpaces) space: const [],
  };
  final Map<String, Object?> _messageErrors = {};
  final Set<String> _loadingSpaces = {...messageSpaces};
  final Set<String> _loadingOlderSpaces = {};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupSub;
  StreamSubscription<MessageVisibilityState>? _visibilitySubscription;
  MessageVisibilityState? _visibilityState;
  Object? _visibilityError;
  bool _loadingVisibility = true;
  bool _disposed = false;

  GroupModel group;

  StudyRoomController({
    required this.group,
    FirebaseFirestore? firestore,
    ChatService? chatService,
  }) : groupId = group.id,
       firestore = firestore ?? FirebaseFirestore.instance,
       chatService = chatService ?? ChatService();

  List<MessageModel> messagesFor(String space, {required String userId}) {
    final visibilityState = _visibilityState;
    if (visibilityState == null) return const [];
    return (_messagesBySpace[space] ?? const [])
        .where((message) => visibilityState.allows(message, userId: userId))
        .toList(growable: false);
  }

  bool hasMore(String space) => _pagers[space]?.hasMore ?? false;

  bool loadingMessages(String space) =>
      _loadingVisibility || _loadingSpaces.contains(space);

  bool loadingOlder(String space) => _loadingOlderSpaces.contains(space);

  Object? messageError(String space) =>
      _visibilityError ?? _messageErrors[space];

  void initialize() {
    _groupSub = firestore.collection('groups').doc(groupId).snapshots().listen((
      snapshot,
    ) {
      if (snapshot.exists) {
        group = GroupModel.fromFirestore(snapshot);
        _notify();
      }
    });

    _visibilitySubscription = chatService
        .watchMessageVisibility(groupId)
        .listen(
          (state) {
            _visibilityState = state;
            _visibilityError = null;
            _loadingVisibility = false;
            _notify();
          },
          onError: (Object error) {
            _visibilityError = error;
            _loadingVisibility = false;
            _notify();
          },
        );

    for (final space in messageSpaces) {
      final pager = chatService.createMessagePager(groupId, space: space);
      _pagers[space] = pager;
      _messageSubscriptions[space] = pager.stream.listen(
        (messages) {
          _messagesBySpace[space] = messages;
          _messageErrors.remove(space);
          _loadingSpaces.remove(space);
          _notify();
        },
        onError: (Object error) {
          _messageErrors[space] = error;
          _loadingSpaces.remove(space);
          _notify();
        },
      );
    }
  }

  Future<void> loadOlder(String space) async {
    final pager = _pagers[space];
    if (pager == null ||
        _loadingOlderSpaces.contains(space) ||
        !pager.hasMore) {
      return;
    }
    _loadingOlderSpaces.add(space);
    _notify();
    try {
      await pager.loadOlder();
      _messageErrors.remove(space);
    } catch (error) {
      _messageErrors[space] = error;
    } finally {
      _loadingOlderSpaces.remove(space);
      _notify();
    }
  }

  Future<void> hideMessageForMe(String messageId) async {
    final previousState = _visibilityState;
    if (previousState == null) {
      throw StateError('Personal room state is not loaded yet.');
    }
    final optimisticState = MessageVisibilityState(
      hiddenMessageIds: {...previousState.hiddenMessageIds, messageId},
      clearedBefore: previousState.clearedBefore,
    );
    _visibilityState = optimisticState;
    _notify();
    try {
      await chatService.deleteMessageForMe(groupId, messageId);
    } catch (_) {
      if (identical(_visibilityState, optimisticState)) {
        _visibilityState = previousState;
        _notify();
      }
      rethrow;
    }
  }

  Future<void> clearChatForMe() async {
    final previousState = _visibilityState;
    if (previousState == null) {
      throw StateError('Personal room state is not loaded yet.');
    }
    final optimisticState = MessageVisibilityState(
      hiddenMessageIds: previousState.hiddenMessageIds,
      clearedBefore: DateTime.now(),
    );
    _visibilityState = optimisticState;
    _notify();
    try {
      await chatService.clearChatForMe(groupId);
    } catch (_) {
      if (identical(_visibilityState, optimisticState)) {
        _visibilityState = previousState;
        _notify();
      }
      rethrow;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_groupSub?.cancel());
    unawaited(_visibilitySubscription?.cancel());
    for (final subscription in _messageSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final pager in _pagers.values) {
      unawaited(pager.dispose());
    }
    super.dispose();
  }
}
