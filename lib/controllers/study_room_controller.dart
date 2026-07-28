import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';

class StudyRoomController extends ChangeNotifier {
  final String groupId;
  final FirebaseFirestore firestore;
  final ChatService chatService;

  late final GroupMessagePager _pager;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupSub;
  StreamSubscription<List<MessageModel>>? _messageSub;

  GroupModel group;
  List<MessageModel> messages = const [];
  Object? messageError;
  bool loadingMessages = true;
  bool loadingOlder = false;
  bool _disposed = false;

  StudyRoomController({
    required this.group,
    FirebaseFirestore? firestore,
    ChatService? chatService,
  }) : groupId = group.id,
       firestore = firestore ?? FirebaseFirestore.instance,
       chatService = chatService ?? ChatService();

  bool get hasMore => _pager.hasMore;

  void initialize() {
    _pager = chatService.createMessagePager(groupId);
    _groupSub = firestore.collection('groups').doc(groupId).snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          group = GroupModel.fromFirestore(snapshot);
          _notify();
        }
      },
    );
    _messageSub = _pager.stream.listen(
      (value) {
        messages = value;
        messageError = null;
        loadingMessages = false;
        _notify();
      },
      onError: (Object error) {
        messageError = error;
        loadingMessages = false;
        _notify();
      },
    );
  }

  Future<void> loadOlder() async {
    if (loadingOlder || !_pager.hasMore) return;
    loadingOlder = true;
    _notify();
    try {
      await _pager.loadOlder();
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_groupSub?.cancel());
    unawaited(_messageSub?.cancel());
    unawaited(_pager.dispose());
    super.dispose();
  }
}
