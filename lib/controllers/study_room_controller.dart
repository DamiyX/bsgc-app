import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';

class ActiveRoomReadReconciler {
  final Future<void> Function() _acknowledge;
  Future<void>? _inFlight;
  bool _repeatRequested = false;
  bool _active = true;

  ActiveRoomReadReconciler(this._acknowledge);

  Future<void> setActive(bool active) {
    _active = active;
    return active ? reconcile() : Future<void>.value();
  }

  Future<void> reconcile({bool force = false}) {
    if (!_active && !force) return Future<void>.value();
    final active = _inFlight;
    if (active != null) {
      _repeatRequested = true;
      return active.then((_) => _inFlight ?? Future<void>.value());
    }

    final operation = _run();
    _inFlight = operation;
    return operation;
  }

  Future<void> _run() async {
    try {
      do {
        _repeatRequested = false;
        await _acknowledge();
      } while (_repeatRequested);
    } finally {
      _inFlight = null;
    }
  }
}

class DraftReplyReference {
  final String? messageId;
  final MessageModel? message;

  const DraftReplyReference({required this.messageId, required this.message});

  factory DraftReplyReference.restore(
    String? messageId,
    Iterable<MessageModel> availableMessages,
  ) {
    return DraftReplyReference(
      messageId: messageId,
      message: _findMessage(messageId, availableMessages),
    );
  }

  DraftReplyReference reconcile(Iterable<MessageModel> availableMessages) {
    if (message != null || messageId == null) return this;
    return DraftReplyReference(
      messageId: messageId,
      message: _findMessage(messageId, availableMessages),
    );
  }

  static MessageModel? _findMessage(
    String? messageId,
    Iterable<MessageModel> messages,
  ) {
    if (messageId == null) return null;
    for (final message in messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }
}

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
  late final ActiveRoomReadReconciler _readReconciler =
      ActiveRoomReadReconciler(() => chatService.resetUnreadCount(groupId));

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

  Iterable<MessageModel> get allLoadedMessages sync* {
    for (final messages in _messagesBySpace.values) {
      yield* messages;
    }
  }

  Iterable<MessageModel> visibleLoadedMessages(String userId) sync* {
    for (final space in messageSpaces) {
      yield* messagesFor(space, userId: userId);
    }
  }

  void initialize() {
    unawaited(reconcileUnread());
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
          unawaited(reconcileUnread());
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

  Future<void> reconcileUnread() async {
    try {
      await _readReconciler.reconcile();
    } catch (_) {
      // Message streams and lifecycle resume provide the next retry opportunity.
    }
  }

  Future<void> _reconcileUnreadBeforeDispose() async {
    try {
      await _readReconciler.reconcile(force: true);
    } catch (_) {
      // Disposal has no surface for retry; avoid leaking an unhandled timeout.
    }
  }

  Future<void> setRoomActive(bool active) => _readReconciler.setActive(active);

  Future<void> retryMessages(String space) async {
    final pager = _pagers[space];
    if (pager == null) return;
    _messageErrors.remove(space);
    _loadingSpaces.add(space);
    _notify();
    try {
      await pager.retry();
    } catch (error) {
      _messageErrors[space] = error;
      _loadingSpaces.remove(space);
      _notify();
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
    unawaited(_reconcileUnreadBeforeDispose());
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
