import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../controllers/study_room_controller.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/audio_service.dart';
import '../services/chat_service.dart';
import '../services/draft_service.dart';
import '../services/message_outbox_service.dart';
import '../services/voice_cache_service.dart';
import '../theme.dart';
import '../widgets/add_member_sheet.dart';
import '../widgets/braid_media.dart';
import '../widgets/clickable_scripture_text.dart';
import '../widgets/report_dialog.dart';
import '../widgets/voice_message_bubble.dart';
import 'group_details_screen.dart';

enum StudySpace { plan, reflection, discussion, prayer }

extension on StudySpace {
  String get wireName => switch (this) {
    StudySpace.plan => 'plan',
    StudySpace.reflection => 'reflection',
    StudySpace.discussion => 'discussion',
    StudySpace.prayer => 'prayer',
  };

  String get label => switch (this) {
    StudySpace.plan => 'Plan',
    StudySpace.reflection => 'Reflections',
    StudySpace.discussion => 'Discussion',
    StudySpace.prayer => 'Prayer',
  };

  IconData get icon => switch (this) {
    StudySpace.plan => Icons.route_outlined,
    StudySpace.reflection => Icons.lightbulb_outline_rounded,
    StudySpace.discussion => Icons.forum_outlined,
    StudySpace.prayer => Icons.volunteer_activism_outlined,
  };
}

class StudyRoomScreen extends StatefulWidget {
  final GroupModel group;
  final bool showAddMemberPrompt;
  final String? initialSpace;
  final String? targetMessageId;
  final VoidCallback? onTargetResolved;

  const StudyRoomScreen({
    super.key,
    required this.group,
    this.showAddMemberPrompt = false,
    this.initialSpace,
    this.targetMessageId,
    this.onTargetResolved,
  });

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen>
    with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  final DraftService _draftService = DraftService();
  final MessageOutboxService _outboxService = MessageOutboxService();
  final AudioService _audioService = AudioService();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  final GlobalKey _targetMessageKey = GlobalKey();

  late final StudyRoomController _controller;
  StudySpace _selectedSpace = StudySpace.discussion;
  List<MessagePart> _draftParts = [];
  String? _draftMessageId;
  String? _replyToMessageId;
  MessageModel? _replyToMessage;
  List<OutboxMessage> _outbox = const [];
  String? _outboxLoadError;
  final Set<String> _sendingOutboxIds = {};
  Timer? _draftTimer;
  Timer? _recordingTimer;
  bool _restoringDraft = false;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  double? _pendingTopicProgress;
  final Set<int> _savingChapters = {};
  bool _isResolvingTarget = false;
  bool _targetResolved = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selectedSpace = StudySpace.values.firstWhere(
      (space) =>
          space != StudySpace.plan && space.wireName == widget.initialSpace,
      orElse: () => StudySpace.discussion,
    );
    WidgetsBinding.instance.addObserver(this);
    _controller = StudyRoomController(
      group: widget.group,
      chatService: _chatService,
    );
    _controller.addListener(_handleControllerUpdate);
    _controller.initialize();
    _textController.addListener(_scheduleDraftSave);
    _messageScrollController.addListener(_handleMessageScroll);
    unawaited(_restoreDraft());
    unawaited(_reloadOutbox(autoRetry: true));

    if (widget.showAddMemberPrompt && widget.group.ownerId == _uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddMembers();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_persistDraft());
    _textController
      ..removeListener(_scheduleDraftSave)
      ..dispose();
    _messageScrollController
      ..removeListener(_handleMessageScroll)
      ..dispose();
    _audioService.dispose();
    unawaited(_tts.stop());
    _controller
      ..removeListener(_handleControllerUpdate)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.setRoomActive(true));
    } else {
      unawaited(_controller.setRoomActive(false));
    }
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    unawaited(_revealTargetMessage());
    if (_replyToMessageId == null || _replyToMessage != null) return;
    final reference = DraftReplyReference.restore(
      _replyToMessageId,
      _controller.visibleLoadedMessages(_uid),
    );
    if (reference.message == null) return;
    setState(() => _replyToMessage = reference.message);
  }

  Future<void> _revealTargetMessage() async {
    final targetId = widget.targetMessageId;
    if (_targetResolved ||
        _isResolvingTarget ||
        targetId == null ||
        targetId.isEmpty ||
        (widget.initialSpace != null &&
            _selectedSpace.wireName != widget.initialSpace) ||
        !mounted) {
      return;
    }
    _isResolvingTarget = true;
    final space = _selectedSpace.wireName;
    try {
      final visibleMessages = _controller.messagesFor(space, userId: _uid);
      if (visibleMessages.any((message) => message.id == targetId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _targetResolved) return;
          final context = _targetMessageKey.currentContext;
          if (context == null) {
            unawaited(_revealTargetMessage());
            return;
          }
          _targetResolved = true;
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.5,
          );
          widget.onTargetResolved?.call();
        });
        return;
      }

      final targetWasHidden = _controller.allLoadedMessages.any(
        (message) => message.id == targetId,
      );
      if (targetWasHidden || !_controller.hasMore(space)) {
        _targetResolved = true;
        widget.onTargetResolved?.call();
        if (mounted) {
          _showMessage(
            targetWasHidden
                ? 'That message is hidden from your room.'
                : 'That message is no longer available.',
          );
        }
        return;
      }

      await _controller.loadOlder(space);
    } finally {
      _isResolvingTarget = false;
    }
    if (mounted &&
        !_targetResolved &&
        _controller.messageError(space) == null) {
      await Future<void>.delayed(Duration.zero);
      unawaited(_revealTargetMessage());
    }
  }

  void _handleMessageScroll() {
    if (!_messageScrollController.hasClients) return;
    final position = _messageScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      unawaited(_controller.loadOlder(_selectedSpace.wireName));
    }
  }

  Future<void> _restoreDraft() async {
    if (_uid.isEmpty) return;
    final draft = await _draftService.load(
      userId: _uid,
      groupId: widget.group.id,
    );
    if (draft == null || !mounted) return;
    final restoredSpace = StudySpace.values.firstWhere(
      (space) => space.wireName == draft.space,
      orElse: () => StudySpace.discussion,
    );
    final replyReference = DraftReplyReference.restore(
      draft.replyToMessageId,
      _controller.messagesFor(restoredSpace.wireName, userId: _uid),
    );
    _restoringDraft = true;
    setState(() {
      _selectedSpace = widget.initialSpace == null
          ? restoredSpace == StudySpace.plan
                ? StudySpace.discussion
                : restoredSpace
          : _selectedSpace;
      _textController.text = draft.text;
      _draftParts = List.of(draft.parts);
      _draftMessageId = draft.clientMessageId;
      _replyToMessageId = replyReference.messageId;
      _replyToMessage = replyReference.message;
    });
    _restoringDraft = false;
  }

  void _scheduleDraftSave() {
    if (_restoringDraft) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_persistDraft()),
    );
  }

  Future<void> _persistDraft() async {
    if (_uid.isEmpty) return;
    await _draftService.save(
      userId: _uid,
      groupId: widget.group.id,
      draft: GroupDraft(
        text: _textController.text,
        parts: List.of(_draftParts),
        space: _selectedSpace.wireName,
        replyToMessageId: _replyToMessageId,
        clientMessageId: _draftMessageId,
      ),
    );
  }

  void _selectSpace(StudySpace space) {
    if (_selectedSpace == space) return;
    setState(() => _selectedSpace = space);
    _scheduleDraftSave();
    unawaited(_revealTargetMessage());
  }

  Future<void> _reloadOutbox({bool autoRetry = false}) async {
    if (_uid.isEmpty) return;
    late final List<OutboxMessage> entries;
    try {
      entries = await _outboxService.list(
        userId: _uid,
        groupId: widget.group.id,
      );
    } on OutboxDataException {
      if (mounted) {
        setState(() {
          _outboxLoadError =
              'Saved uploads could not be checked. Try loading them again.';
        });
      }
      return;
    } on FileSystemException {
      if (mounted) {
        setState(() {
          _outboxLoadError =
              'Saved uploads are temporarily unavailable on this device.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _outbox = entries;
      _outboxLoadError = null;
    });
    if (autoRetry) {
      for (final entry in entries.where(
        (item) => item.canAttempt(manual: false, now: DateTime.now()),
      )) {
        if (!mounted) return;
        await _attemptOutbox(entry, quiet: true, manual: false);
      }
    }
  }

  Future<void> _attemptOutbox(
    OutboxMessage entry, {
    bool quiet = false,
    bool manual = true,
  }) async {
    if (_sendingOutboxIds.contains(entry.id)) return;
    setState(() => _sendingOutboxIds.add(entry.id));
    try {
      await _outboxService.send(
        entry,
        chatService: _chatService,
        manual: manual,
      );
      await _reloadOutbox();
    } catch (_) {
      await _reloadOutbox();
      if (!quiet && mounted) {
        _showMessage(
          'Still offline. Your reflection is saved here and can be retried.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingOutboxIds.remove(entry.id));
      }
    }
  }

  Future<void> _removeOutbox(OutboxMessage entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this unsent reflection?'),
        content: const Text(
          'Its text and any local attachment will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _outboxService.remove(entry);
    await _reloadOutbox();
  }

  Future<void> _sendDraft() async {
    if (_uid.isEmpty || _selectedSpace == StudySpace.plan) return;
    final text = _textController.text.trim();
    if (text.length > 8000) {
      _showMessage('Keep each reflection under 8,000 characters.');
      return;
    }
    final parts = <MessagePart>[
      if (text.isNotEmpty) MessagePart(type: MessageType.text, content: text),
      ..._draftParts,
    ];
    if (parts.isEmpty || parts.length > 4) {
      _showMessage('A reflection can contain up to four parts.');
      return;
    }

    final messageId = _draftMessageId ?? _chatService.createClientMessageId();
    late final OutboxMessage entry;
    try {
      entry = await _outboxService.enqueue(
        id: messageId,
        userId: _uid,
        groupId: widget.group.id,
        space: _selectedSpace.wireName,
        parts: parts,
        replyToMessageId: _replyToMessageId,
      );
    } on OutboxQuotaException catch (error) {
      _showMessage(error.message);
      return;
    }

    _restoringDraft = true;
    setState(() {
      _textController.clear();
      _draftParts = [];
      _draftMessageId = null;
      _replyToMessageId = null;
      _replyToMessage = null;
    });
    _restoringDraft = false;
    await _draftService.clear(userId: _uid, groupId: widget.group.id);
    await _reloadOutbox();
    await _attemptOutbox(entry);
  }

  String _ensureDraftMessageId() {
    return _draftMessageId ??= _chatService.createClientMessageId();
  }

  Future<void> _addImage() async {
    if (_draftParts.length >= 3) {
      _showMessage('A reflection can contain up to four parts.');
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (picked == null) return;
    try {
      final source = await picked.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        source,
        minWidth: 1600,
        minHeight: 1600,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      final localUri = await _outboxService.persistAttachment(
        userId: _uid,
        groupId: widget.group.id,
        messageId: _ensureDraftMessageId(),
        bytes: compressed,
        extension: 'jpg',
      );
      if (!mounted) return;
      setState(() {
        _draftParts.add(
          MessagePart(type: MessageType.image, content: localUri),
        );
      });
      _scheduleDraftSave();
    } on OutboxQuotaException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'That photo could not be prepared. Choose another photo and try again.',
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _finishRecording();
      return;
    }
    if (_draftParts.length >= 3) {
      _showMessage('A reflection can contain up to four parts.');
      return;
    }
    final started = await _audioService.startRecording();
    if (!started) {
      _showMessage(
        'Microphone access is needed only to record a voice reflection.',
      );
      return;
    }
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 300) {
        unawaited(_finishRecording());
      }
    });
  }

  Future<void> _finishRecording() async {
    _recordingTimer?.cancel();
    final path = await _audioService.stopRecording();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;
    try {
      final recording = await _audioService.prepareRecording(path);
      final localUri = await _outboxService.persistAttachment(
        userId: _uid,
        groupId: widget.group.id,
        messageId: _ensureDraftMessageId(),
        bytes: recording.bytes,
        extension: 'm4a',
      );
      await _audioService.deletePreparedRecording(recording);
      if (!mounted) return;
      setState(() {
        _draftParts.add(
          MessagePart(
            type: MessageType.voice,
            content: localUri,
            durationSeconds: recording.durationSeconds,
          ),
        );
        _recordingSeconds = 0;
      });
      _scheduleDraftSave();
    } on OutboxQuotaException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'The recording is saved locally, but could not be prepared.',
      );
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioService.cancelRecording();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }
  }

  void _removeDraftPart(int index) {
    final part = _draftParts[index];
    setState(() => _draftParts.removeAt(index));
    final uri = Uri.tryParse(part.content);
    if (uri?.scheme == 'file') {
      unawaited(_deleteLocalFile(uri!));
    }
    _scheduleDraftSave();
  }

  Future<void> _deleteLocalFile(Uri uri) async {
    try {
      final file = File.fromUri(uri);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The draft is already detached; stale files are cleaned with the outbox.
    }
  }

  void _showAddMembers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMemberSheet(groupId: widget.group.id),
    );
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this view?'),
        content: const Text(
          'Earlier messages will be hidden only for you. Other group members keep their copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear for me'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.clearChatForMe();
      _showMessage('Earlier messages are now hidden for you.');
    } catch (_) {
      _showMessage('Could not clear the room right now.');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final group = _controller.group;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Semantics(
              button: true,
              label: 'Open details for ${group.name}',
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailsScreen(group: group),
                  ),
                ),
                child: Row(
                  children: [
                    BraidCoverImage(
                      identity: group.id,
                      imageUrl: group.photoUrl,
                      width: 38,
                      height: 38,
                      borderRadius: 9,
                      semanticLabel: '${group.name} cover',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${group.members.length} members • ${_lifecycleText(group)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Study group actions',
                onSelected: (value) {
                  if (value == 'details') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupDetailsScreen(group: group),
                      ),
                    );
                  } else if (value == 'invite') {
                    _showAddMembers();
                  } else if (value == 'clear') {
                    unawaited(_clearChat());
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('Group details'),
                  ),
                  if (group.ownerId == _uid)
                    const PopupMenuItem(
                      value: 'invite',
                      child: Text('Invite members'),
                    ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear messages for me'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                _StudySpaceSelector(
                  selected: _selectedSpace,
                  onSelected: _selectSpace,
                ),
                Expanded(
                  child: _selectedSpace == StudySpace.plan
                      ? _buildPlan(group)
                      : _buildMessageSpace(group),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlan(GroupModel group) {
    final progress = (group.readingProgress[_uid] ?? 0).clamp(0, 1);
    final completed = List<int>.from(
      group.userCompletedChapters[_uid] ?? const [],
    )..sort();
    final endLabel = group.endDate == null
        ? 'No end date'
        : DateFormat('MMM d, yyyy').format(group.endDate!);

    return ListView(
      key: const PageStorageKey('study-plan'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.groupType == 'Bible'
                            ? group.studyBook ?? 'Bible study'
                            : group.topic ?? 'Topic study',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Chip(label: Text(_lifecycleText(group))),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${(progress * 100).round()}% complete • Ends $endLabel'),
                const SizedBox(height: 12),
                Semantics(
                  label: '${(progress * 100).round()} percent complete',
                  child: LinearProgressIndicator(
                    value: progress.toDouble(),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                if (group.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(group.description.trim()),
                ],
              ],
            ),
          ),
        ),
        if (group.pinnedScripture.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Focus scripture',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  ClickableScriptureText(
                    text: group.pinnedScripture,
                    style: Theme.of(context).textTheme.bodyLarge!,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (group.groupType == 'Bible' && group.totalChapters > 0) ...[
          Text(
            'Your reading progress',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Mark a chapter after you finish it. This is personal progress, not a competition.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 64,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: group.totalChapters,
            itemBuilder: (context, index) {
              final chapter = index + 1;
              final selected = completed.contains(chapter);
              final saving = _savingChapters.contains(chapter);
              return Semantics(
                button: true,
                selected: selected,
                label:
                    'Chapter $chapter, ${selected ? 'complete' : 'not complete'}'
                    '${saving ? ', saving' : ''}',
                child: FilterChip(
                  selected: selected,
                  showCheckmark: false,
                  label: Text('$chapter'),
                  onSelected: group.lifecycle == 'active' && !saving
                      ? (_) => _toggleChapter(group, chapter)
                      : null,
                ),
              );
            },
          ),
        ] else ...[
          Text(
            'Your study progress',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Slider(
            value: _pendingTopicProgress ?? progress.toDouble(),
            divisions: 10,
            label:
                '${((_pendingTopicProgress ?? progress.toDouble()) * 100).round()}%',
            onChanged: group.lifecycle == 'active'
                ? (value) => setState(() => _pendingTopicProgress = value)
                : null,
            onChangeEnd: group.lifecycle == 'active'
                ? (value) => _saveTopicProgress(group, value)
                : null,
          ),
        ],
        if (group.lifecycle == 'completed') ...[
          const SizedBox(height: 22),
          _CompletedRecap(group: group),
        ],
      ],
    );
  }

  Future<void> _toggleChapter(GroupModel group, int chapter) async {
    setState(() => _savingChapters.add(chapter));
    try {
      await _chatService.toggleGroupStudyChapter(
        group.id,
        chapter: chapter,
        totalChapters: group.totalChapters,
      );
    } catch (_) {
      _showMessage('Progress could not be updated yet.');
    } finally {
      if (mounted) setState(() => _savingChapters.remove(chapter));
    }
  }

  Future<void> _saveTopicProgress(GroupModel group, double progress) async {
    try {
      await _chatService.updateReadingProgress(group.id, progress);
    } catch (_) {
      _showMessage('Progress could not be updated yet.');
    } finally {
      if (mounted) setState(() => _pendingTopicProgress = null);
    }
  }

  Widget _buildMessageSpace(GroupModel group) {
    final space = _selectedSpace.wireName;
    final messages = _controller.messagesFor(space, userId: _uid);
    final messageError = _controller.messageError(space);
    return Column(
      children: [
        if (messageError != null && messages.isNotEmpty)
          const _OfflineMessageBanner(),
        if (_outboxLoadError != null)
          MaterialBanner(
            leading: const Icon(Icons.warning_amber_rounded),
            content: Text(_outboxLoadError!),
            actions: [
              TextButton(
                onPressed: _reloadOutbox,
                child: const Text('Try again'),
              ),
            ],
          ),
        if (_outbox.isNotEmpty)
          _OutboxStrip(
            entries: _outbox
                .where(
                  (entry) =>
                      entry.status == OutboxStatus.corrupt ||
                      entry.space == _selectedSpace.wireName,
                )
                .toList(),
            sendingIds: _sendingOutboxIds,
            onRetry: _attemptOutbox,
            onDiscard: _removeOutbox,
          ),
        Expanded(
          child: _controller.loadingMessages(space) && messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : messageError != null && messages.isEmpty
              ? _RoomLoadError(onRetry: () => _controller.retryMessages(space))
              : messages.isEmpty
              ? _EmptyStudySpace(
                  space: _selectedSpace,
                  onLoadOlder: _controller.hasMore(space)
                      ? () => _controller.loadOlder(space)
                      : null,
                )
              : ListView.builder(
                  key: PageStorageKey(_selectedSpace.wireName),
                  controller: _messageScrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount:
                      messages.length +
                      (_controller.loadingOlder(space) ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final message = messages[index];
                    final card = _MessageCard(
                      message: message,
                      isMine: message.senderId == _uid,
                      reply: _findReply(message),
                      onReply: () {
                        setState(() {
                          _replyToMessageId = message.id;
                          _replyToMessage = message;
                        });
                        _scheduleDraftSave();
                      },
                      onMore: () => _showMessageActions(message),
                    );
                    return message.id == widget.targetMessageId
                        ? KeyedSubtree(key: _targetMessageKey, child: card)
                        : card;
                  },
                ),
        ),
        if (group.lifecycle == 'active')
          _buildComposer()
        else
          _ReadOnlyComposer(group: group),
      ],
    );
  }

  MessageModel? _findReply(MessageModel message) {
    final replyId = message.replyToMessageId;
    if (replyId == null) return null;
    try {
      return _controller
          .messagesFor(message.space, userId: _uid)
          .firstWhere((item) => item.id == replyId);
    } catch (_) {
      return null;
    }
  }

  Widget _buildComposer() {
    final semantic = Theme.of(context).extension<BraidSemanticColors>();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _selectedSpace.icon,
                    size: 16,
                    color: semantic?.groupAudience,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Visible to ${_controller.group.name}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: semantic?.groupAudience,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (_replyToMessageId != null)
                _ReplyPreview(
                  message: _replyToMessage,
                  onClose: () {
                    setState(() {
                      _replyToMessageId = null;
                      _replyToMessage = null;
                    });
                    _scheduleDraftSave();
                  },
                ),
              if (_draftParts.isNotEmpty)
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: _draftParts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => _DraftPartPreview(
                      part: _draftParts[index],
                      onRemove: () => _removeDraftPart(index),
                    ),
                  ),
                ),
              if (_isRecording)
                _RecordingBar(
                  seconds: _recordingSeconds,
                  onCancel: _cancelRecording,
                  onDone: _finishRecording,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Attach a photo',
                      onPressed: _addImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 6,
                        maxLength: 8000,
                        buildCounter:
                            (
                              context, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => currentLength > 7600
                            ? Text('$currentLength/$maxLength')
                            : null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: switch (_selectedSpace) {
                            StudySpace.reflection => 'What stood out to you?',
                            StudySpace.prayer => 'Share a prayer or request…',
                            _ => 'Add to the discussion…',
                          },
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Record a voice reflection',
                      onPressed: _toggleRecording,
                      icon: const Icon(Icons.mic_none_rounded),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, _) {
                        final enabled =
                            value.text.trim().isNotEmpty ||
                            _draftParts.isNotEmpty;
                        return IconButton.filled(
                          tooltip: 'Send to ${_selectedSpace.label}',
                          onPressed: enabled ? _sendDraft : null,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMessageActions(MessageModel message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _replyToMessageId = message.id;
                  _replyToMessage = message;
                });
                _scheduleDraftSave();
              },
            ),
            if (_messageText(message).isNotEmpty)
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(
                    ClipboardData(text: _messageText(message)),
                  );
                  _showMessage('Copied');
                },
              ),
            if (_messageText(message).isNotEmpty)
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Read aloud'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_tts.speak(_messageText(message)));
                },
              ),
            if (message.senderId == _uid)
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_deleteMessage(message));
                },
              )
            else ...[
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide for me'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_hideMessage(message));
                },
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    showReportDialog(
                      context,
                      targetType: 'message',
                      targetId: message.id,
                      groupId: widget.group.id,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessageModel message) async {
    try {
      await _chatService.deleteMessage(widget.group.id, message.id);
    } catch (_) {
      _showMessage('That message could not be deleted.');
    }
  }

  Future<void> _hideMessage(MessageModel message) async {
    try {
      await _controller.hideMessageForMe(message.id);
      _showMessage('Message hidden for you.');
    } catch (_) {
      _showMessage('That message could not be hidden.');
    }
  }

  String _messageText(MessageModel message) {
    return message.parts
        .where((part) => part.type == MessageType.text)
        .map((part) => part.content)
        .join('\n\n');
  }
}

String _lifecycleText(GroupModel group) {
  switch (group.lifecycle) {
    case 'scheduled':
      return group.startDate == null
          ? 'scheduled'
          : 'starts ${DateFormat('MMM d, h:mm a').format(group.startDate!)} '
                '${group.startDate!.timeZoneName}';
    case 'completed':
      return 'completed';
    case 'archived':
      return 'archived';
    default:
      return 'active';
  }
}

class _StudySpaceSelector extends StatelessWidget {
  final StudySpace selected;
  final ValueChanged<StudySpace> onSelected;

  const _StudySpaceSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        scrollDirection: Axis.horizontal,
        itemCount: StudySpace.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final space = StudySpace.values[index];
          return ChoiceChip(
            avatar: Icon(space.icon, size: 18),
            label: Text(space.label),
            selected: selected == space,
            onSelected: (_) => onSelected(space),
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final MessageModel message;
  final MessageModel? reply;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onMore;

  const _MessageCard({
    required this.message,
    required this.reply,
    required this.isMine,
    required this.onReply,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: message.hasKnownTimestamp
          ? '${message.senderName}, ${DateFormat('MMM d, h:mm a').format(message.timestamp)}'
          : '${message.senderName}, time unavailable',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isMine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isMine) ...[
              BraidAvatar(
                identity: message.senderId,
                displayName: message.senderName,
                imageUrl: message.senderPhotoUrl,
                radius: 18,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: isMine
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isMine ? 'You' : message.senderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Message actions',
                            visualDensity: VisualDensity.compact,
                            onPressed: onMore,
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (reply != null)
                      InkWell(
                        onTap: onReply,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${reply!.senderName}: ${_summary(reply!)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    if (message.isDeleted)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'This message was deleted',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final part in message.parts)
                        _MessagePartView(part: part, isMine: isMine),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.hasKnownTimestamp
                                ? DateFormat('h:mm a').format(message.timestamp)
                                : 'Time unavailable',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          if (message.isPending) ...[
                            const SizedBox(width: 5),
                            const Tooltip(
                              message: 'Waiting to sync',
                              child: Icon(Icons.schedule_rounded, size: 14),
                            ),
                          ] else if (message.isFromCache) ...[
                            const SizedBox(width: 5),
                            const Tooltip(
                              message: 'Saved offline copy',
                              child: Icon(Icons.offline_pin_outlined, size: 14),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isMine) const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  static String _summary(MessageModel message) {
    for (final part in message.parts) {
      if (part.type == MessageType.text) return part.content;
      if (part.type == MessageType.voice) return 'Voice reflection';
      if (part.type == MessageType.image) return 'Photo';
    }
    return 'Message';
  }
}

class _MessagePartView extends StatelessWidget {
  final MessagePart part;
  final bool isMine;

  const _MessagePartView({required this.part, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (part.type == MessageType.text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: ClickableScriptureText(
          text: part.content,
          style: Theme.of(context).textTheme.bodyLarge!,
        ),
      );
    }
    if (!part.hasCanonicalManagedIdentity) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          label: 'External media link. Media is not loaded automatically.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_rounded, size: 18),
                  SizedBox(width: 6),
                  Text('External media link'),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                part.content,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    if (part.type == MessageType.voice) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: VoiceMessageBubble(
          audioUrl: 'firebase-storage:///${part.content}',
          isMe: false,
          durationSeconds: part.durationSeconds ?? 1,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    if (part.type == MessageType.image) {
      return _AuthenticatedImagePart(storagePath: part.content);
    }
    return const SizedBox.shrink();
  }
}

class _AuthenticatedImagePart extends StatefulWidget {
  final String storagePath;

  const _AuthenticatedImagePart({required this.storagePath});

  @override
  State<_AuthenticatedImagePart> createState() =>
      _AuthenticatedImagePartState();
}

class _AuthenticatedImagePartState extends State<_AuthenticatedImagePart> {
  late Future<VoiceCacheEntry> _entry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final accountId = FirebaseAuth.instance.currentUser?.uid;
    _entry = accountId == null
        ? Future.error(StateError('Sign in to view this image.'))
        : VoiceCacheService.shared.prepare(
            accountId: accountId,
            sourceUrl: 'firebase-storage:///${widget.storagePath}',
          );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Semantics(
        image: true,
        label: 'Shared study image',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<VoiceCacheEntry>(
            future: _entry,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  width: 280,
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entry = snapshot.data;
              if (snapshot.hasError || entry == null) {
                return Container(
                  width: 280,
                  height: 220,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_not_supported_outlined),
                      const SizedBox(height: 6),
                      const Text('Image unavailable or access revoked'),
                      TextButton(
                        onPressed: () => setState(_load),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return Image.file(
                entry.file,
                width: 280,
                height: 220,
                cacheWidth: 840,
                fit: BoxFit.cover,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DraftPartPreview extends StatelessWidget {
  final MessagePart part;
  final VoidCallback onRemove;

  const _DraftPartPreview({required this.part, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(part.content);
    final isFile = uri?.scheme == 'file';
    return Stack(
      children: [
        Container(
          width: 78,
          height: 68,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: part.type == MessageType.image && isFile
              ? Image.file(
                  File.fromUri(uri!),
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                )
              : Icon(
                  part.type == MessageType.voice
                      ? Icons.graphic_eq_rounded
                      : Icons.attachment_rounded,
                ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton.filledTonal(
            tooltip: 'Remove attachment',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
        ),
      ],
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final MessageModel? message;
  final VoidCallback onClose;

  const _ReplyPreview({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final resolvedMessage = message;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              resolvedMessage == null
                  ? 'Replying to an unavailable original message'
                  : 'Replying to ${resolvedMessage.senderName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  const _RecordingBar({
    required this.seconds,
    required this.onCancel,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final duration =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      liveRegion: true,
      label: 'Recording voice reflection, $duration',
      child: Row(
        children: [
          const Icon(Icons.mic_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Text(duration, style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Keep'),
          ),
        ],
      ),
    );
  }
}

class _OutboxStrip extends StatelessWidget {
  final List<OutboxMessage> entries;
  final Set<String> sendingIds;
  final Future<void> Function(OutboxMessage) onRetry;
  final Future<void> Function(OutboxMessage) onDiscard;

  const _OutboxStrip({
    required this.entries,
    required this.sendingIds,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        children: [
          for (final entry in entries)
            Row(
              children: [
                Icon(
                  entry.status == OutboxStatus.failed ||
                          entry.status == OutboxStatus.corrupt
                      ? Icons.error_outline_rounded
                      : Icons.schedule_send_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sendingIds.contains(entry.id)
                        ? 'Sending saved reflection…'
                        : !entry.retryable
                        ? entry.lastError ??
                              'Saved upload needs to be discarded'
                        : entry.status == OutboxStatus.failed
                        ? 'Saved locally • retry waiting'
                        : 'Saved locally • waiting to send',
                  ),
                ),
                if (sendingIds.contains(entry.id))
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (entry.retryable)
                    TextButton(
                      onPressed: () => onRetry(entry),
                      child: const Text('Retry'),
                    ),
                  IconButton(
                    tooltip: 'Discard unsent reflection',
                    onPressed: () => onDiscard(entry),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyStudySpace extends StatelessWidget {
  final StudySpace space;
  final Future<void> Function()? onLoadOlder;

  const _EmptyStudySpace({required this.space, this.onLoadOlder});

  @override
  Widget build(BuildContext context) {
    final text = switch (space) {
      StudySpace.reflection =>
        'What did you notice?\nShare an observation, question, or connection.',
      StudySpace.prayer =>
        'Hold one another in prayer.\nShare a request or a prayer for the group.',
      _ =>
        'The discussion is open.\nAsk a question or build on today’s reading.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(space.icon, size: 46),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onLoadOlder != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onLoadOlder,
                child: const Text('Load older messages'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyComposer extends StatelessWidget {
  final GroupModel group;

  const _ReadOnlyComposer({required this.group});

  @override
  Widget build(BuildContext context) {
    final scheduled = group.lifecycle == 'scheduled';
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(scheduled ? Icons.schedule_rounded : Icons.task_alt_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                scheduled
                    ? 'This study opens ${group.startDate == null ? 'on its scheduled date' : '${DateFormat('MMM d, yyyy, h:mm a').format(group.startDate!)} ${group.startDate!.timeZoneName}'}. Posting may take up to about an hour to unlock.'
                    : 'This study is complete. Its reflections remain available to revisit. Completion status may take up to about an hour to refresh.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedRecap extends StatelessWidget {
  final GroupModel group;

  const _CompletedRecap({required this.group});

  @override
  Widget build(BuildContext context) {
    final average = group.readingProgress.values.isEmpty
        ? 0
        : group.readingProgress.values.reduce((a, b) => a + b) /
              group.readingProgress.values.length;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Study recap',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text('${group.members.length} people studied together'),
            Text('Average personal progress: ${(average * 100).round()}%'),
            if (group.startDate != null && group.endDate != null)
              Text(
                '${DateFormat('MMM d').format(group.startDate!)} – '
                '${DateFormat('MMM d, yyyy').format(group.endDate!)}',
              ),
            const SizedBox(height: 10),
            const Text(
              'Revisit the Reflections tab to remember what the group learned.',
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineMessageBanner extends StatelessWidget {
  const _OfflineMessageBanner();

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.cloud_off_outlined),
      content: const Text('Showing saved messages while Braid reconnects.'),
      actions: const [SizedBox.shrink()],
    );
  }
}

class _RoomLoadError extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _RoomLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 10),
            const Text('Messages are not available yet.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
