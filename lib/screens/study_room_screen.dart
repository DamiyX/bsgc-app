import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../services/audio_service.dart';
import '../widgets/voice_message_bubble.dart';
import 'group_details_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/scripture_parser.dart';
import '../widgets/bible_verse_bottom_sheet.dart';
import '../widgets/add_member_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

enum TtsState { playing, paused, stopped }


class StudyRoomScreen extends StatefulWidget {
  final GroupModel group;

  const StudyRoomScreen({super.key, required this.group});

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {

  final FlutterTts _flutterTts = FlutterTts();
  String? _speakingMessageId;
  TtsState _ttsState = TtsState.stopped;
  final ChatService _chatService = ChatService();
  final AudioService _audioService = AudioService();
  final TextEditingController _textController = TextEditingController();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  // Progress Ring Toggle State (localized per message)
  final Map<String, bool> _showProgressForMessage = {};
  final Map<String, Timer> _progressTimers = {};
  
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  late Stream<List<MessageModel>> _messagesStream;

  // Hybrid Message Drafts
  List<MessagePart> _draftParts = [];
  String? _replyToMessageId;
  MessageModel? _replyToMessage;
  
  // Editing
  String? _editingMessageId;

  // Scrolling & Highlight
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  bool _showScrollToBottom = false;
  String _lastNewMessageId = '';

  // Pagination
  int _messageLimit = 20;
  bool _isLoadingMore = false;

  void _onScroll() {
    if (_scrollController.hasClients) {
      if (_scrollController.offset > 200 && !_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      } else if (_scrollController.offset <= 200 && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      
      // Load more messages when reaching the top
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore) {
        setState(() {
          _isLoadingMore = true;
          _messageLimit += 20;
          _messagesStream = _chatService.getGroupMessages(widget.group.id, limit: _messageLimit);
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _isLoadingMore = false);
        });
      }
    }
  }

  void _smoothScrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutExpo,
      );
    }
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _messagesStream = _chatService.getGroupMessages(widget.group.id, limit: _messageLimit);
  }

  @override
  void dispose() {
    for (var timer in _progressTimers.values) {
      timer.cancel();
    }
    _recordingTimer?.cancel();
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Color _getAvatarColor(String userId) {
    if (userId == FirebaseAuth.instance.currentUser?.uid) return Colors.green;
    final List<Color> colors = [
      Colors.blue, Colors.orange, Colors.red, Colors.purple,
      Colors.teal, Colors.pink, Colors.indigo, Colors.amber,
      Colors.cyan, Colors.deepOrange, Colors.lime, Colors.brown
    ];
    int index = widget.group.members.indexOf(userId);
    if (index < 0) {
      int asciiSum = 0;
      for (int i = 0; i < userId.length; i++) asciiSum += userId.codeUnitAt(i);
      index = asciiSum;
    }
    return colors[index % colors.length];
  }

  void _startRecording() async {
    if (_textController.text.trim().isNotEmpty) {
      setState(() {
        _draftParts.add(MessagePart(
          type: MessageType.text,
          content: _textController.text.trim(),
        ));
      });
      _textController.clear();
    }

    final started = await _audioService.startRecording();
    if (started) {
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() => _recordingDuration++);
      });
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioService.cancelRecording();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
      });
    }
  }

  void _saveRecordingToDraft() async {
    _recordingTimer?.cancel();
    final path = await _audioService.stopRecording();
    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    }

    if (path != null) {
      try {
        final result = await _audioService.uploadRecording(path);
        if (result != null && mounted) {
          setState(() {
            _draftParts.add(MessagePart(
              type: MessageType.voice,
              content: result['url'],
              durationSeconds: result['duration'],
            ));
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving audio: $e')),
          );
        }
      }
    }
  }

  void _sendDraft() async {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _draftParts.add(MessagePart(type: MessageType.text, content: text));
      _textController.clear();
    }

    if (_draftParts.isEmpty) return;

    final partsToSend = List<MessagePart>.from(_draftParts);
    final replyId = _replyToMessageId;
    final editId = _editingMessageId;

    setState(() {
      _draftParts.clear();
      _replyToMessageId = null;
      _replyToMessage = null;
      _editingMessageId = null;
    });

    try {
      if (editId != null) {
        await _chatService.editMessage(widget.group.id, editId, partsToSend);
      } else {
        _chatService.sendHybridMessage(
          widget.group.id,
          partsToSend,
          replyToMessageId: _replyToMessageId,
        );
        _replyToMessageId = null;
        if (_scrollController.hasClients) {
          _jumpToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving message: $e')),
        );
      }
    }
  }

  void _removeDraftPart(int index) {
    setState(() {
      _draftParts.removeAt(index);
    });
  }

  void _editTextDraftPart(int index) {
    final part = _draftParts[index];
    if (part.type == MessageType.text) {
      setState(() {
        _textController.text = part.content;
        _draftParts.removeAt(index);
      });
    }
  }

  void _setReply(MessageModel msg) {
    setState(() {
      _replyToMessageId = msg.id;
      _replyToMessage = msg;
    });
  }

  void _beginEditMessage(MessageModel msg) {
    setState(() {
      _editingMessageId = msg.id;
      _draftParts = List<MessagePart>.from(msg.parts);
      _replyToMessageId = msg.replyToMessageId;
    });
  }

  void _scrollToMessage(String messageId, List<MessageModel> messages) async {
    var key = _messageKeys[messageId];
    if (key == null || key.currentContext == null) {
      int targetIndex = messages.indexWhere((m) => m.id == messageId);
      if (targetIndex != -1) {
        double targetApprox = targetIndex * 120.0;
        if (targetApprox > _scrollController.position.maxScrollExtent) {
          targetApprox = _scrollController.position.maxScrollExtent;
        }
        _scrollController.jumpTo(targetApprox);
        await Future.delayed(const Duration(milliseconds: 100));

        for (int i = 0; i < 20; i++) {
          if (_messageKeys[messageId]?.currentContext != null) break;

          int currentRenderedIndex = -1;
          for (var m in messages) {
             if (_messageKeys[m.id]?.currentContext != null) {
                currentRenderedIndex = messages.indexWhere((msg) => msg.id == m.id);
                break;
             }
          }

          if (currentRenderedIndex != -1) {
             int diff = targetIndex - currentRenderedIndex;
             double adjustment = diff * 100.0;
             if (adjustment > 1500) adjustment = 1500;
             if (adjustment < -1500) adjustment = -1500;
             
             double nextOffset = _scrollController.offset + adjustment;
             if (nextOffset < 0) nextOffset = 0;
             if (nextOffset > _scrollController.position.maxScrollExtent) nextOffset = _scrollController.position.maxScrollExtent;
             
             _scrollController.jumpTo(nextOffset);
             await Future.delayed(const Duration(milliseconds: 100));
          } else {
             _scrollController.jumpTo(_scrollController.offset + 10);
             await Future.delayed(const Duration(milliseconds: 50));
          }
        }
        key = _messageKeys[messageId];
      }
    }

    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      setState(() {
        _highlightedMessageId = messageId;
      });
      Future.delayed(const Duration(milliseconds: 3500), () {
        if (mounted && _highlightedMessageId == messageId) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message is too far back. Tried scanning, but failed.')),
        );
      }
    }
  }

  Future<void> _uploadAndSendAttachment(Uint8List bytes, String extension, MessageType type, String mimeType) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading ${type.name}...')));
    try {
      Uint8List uploadBytes = bytes;
      if (type == MessageType.image) {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 800,
          minHeight: 800,
          quality: 60,
        );
        uploadBytes = compressed;
      }
      
      final storageRef = FirebaseStorage.instance.ref().child('chat_attachments/${widget.group.id}_${DateTime.now().millisecondsSinceEpoch}.$extension');
      final uploadTask = storageRef.putData(uploadBytes, SettableMetadata(contentType: mimeType));
      final snapshot = await uploadTask;
      
      if (snapshot.state == TaskState.success) {
        final url = await snapshot.ref.getDownloadURL();
        _chatService.sendHybridMessage(
          widget.group.id,
          [MessagePart(type: type, content: url)],
        );
        if (_scrollController.hasClients) {
          _jumpToBottom();
        }
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send ${type.name}: $e')));
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('Image'),
              onTap: () async {
                Navigator.pop(context);
                final result = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (result != null) {
                  final bytes = await result.readAsBytes();
                  _uploadAndSendAttachment(bytes, 'jpg', MessageType.image, 'image/jpeg');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.red),
              title: const Text('Video'),
              onTap: () async {
                Navigator.pop(context);
                final result = await ImagePicker().pickVideo(source: ImageSource.gallery);
                if (result != null) {
                  final bytes = await result.readAsBytes();
                  _uploadAndSendAttachment(bytes, 'mp4', MessageType.video, 'video/mp4');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.orange),
              title: const Text('Document'),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
                if (result != null && result.files.single.bytes != null) {
                  final ext = result.files.single.extension ?? 'file';
                  _uploadAndSendAttachment(result.files.single.bytes!, ext, MessageType.document, 'application/octet-stream');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteMessage(MessageModel msg, bool forEveryone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: Text(forEveryone ? 'Delete this message for everyone?' : 'Delete this message for yourself?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      if (forEveryone) {
        await _chatService.deleteMessage(widget.group.id, msg.id);
      } else {
        await _chatService.deleteMessageForMe(widget.group.id, msg.id);
      }
    }
  }

  void _toggleStar(MessageModel msg) async {
    final isStarred = msg.starredBy.contains(_currentUserId);
    await _chatService.toggleStarMessage(widget.group.id, msg.id, isStarred);
  }

  void _confirmClearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to clear all messages for yourself? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clearing chat...')));
      await _chatService.clearChatForMe(widget.group.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared.')));
    }
  }

  void _showBubbleMenu(MessageModel message) {
    if (message.isDeleted) return;

    final isMe = message.senderId == _currentUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _setReply(message);
              },
            ),
            ListTile(
              leading: Icon(
                message.starredBy.contains(_currentUserId) ? Icons.star : Icons.star_border,
                color: message.starredBy.contains(_currentUserId) ? Colors.orange : null,
              ),
              title: Text(message.starredBy.contains(_currentUserId) ? 'Unstar' : 'Star'),
              onTap: () {
                Navigator.pop(context);
                _toggleStar(message);
              },
            ),
            if (isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _beginEditMessage(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text('Delete for Me', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message, false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message, true);
                },
              ),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _seedMockMessages() async {
    final groupId = widget.group.id;
    // We use totally different strings to ensure different hash codes for high contrast colors
    final pDavidUid = 'user_david_991'; 
    final pDavidName = 'Pastor David';
    final sSarahUid = 'user_sarah_102';
    final sSarahName = 'Sister Sarah';
    final bJohnUid = 'user_john_xyz';
    final bJohnName = 'Brother John';
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'me';
    final myName = FirebaseAuth.instance.currentUser?.displayName ?? 'Me';

    // Clear existing messages to avoid compounding mock data
    final existingMsgs = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .get();
    for (var doc in existingMsgs.docs) {
      await doc.reference.delete();
    }

    Future<void> sendMock(String uid, String name, List<MessagePart> parts, DateTime time) async {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .add({
        'senderId': uid,
        'senderName': name,
        'senderPhotoUrl': null,
        'replyToMessageId': null,
        'parts': parts.map((p) => p.toMap()).toList(),
        'timestamp': Timestamp.fromDate(time),
        'starredBy': [],
        'isDeleted': false,
      });
    }

    final now = DateTime.now();

    await sendMock(pDavidUid, pDavidName, [
      MessagePart(type: MessageType.text, content: 'Welcome everyone! Today we will be looking at Romans 8:1-4.'),
      MessagePart(type: MessageType.text, content: 'This chapter begins with one of the most powerful declarations: "There is therefore now no condemnation..." Before we dive in, let\'s read Genesis 1:1 and compare the concept of light to John 1:1-5.'),
      MessagePart(type: MessageType.text, content: 'Let\'s break down Romans 8:2 together. I encourage you to read it out loud.'),
    ], now.subtract(const Duration(minutes: 60)));

    await sendMock(sSarahUid, sSarahName, [
      MessagePart(type: MessageType.text, content: 'Thank you Pastor David. Romans 8:1 is honestly what kept me anchored last year. It\'s a completely new governing principle.'),
      MessagePart(type: MessageType.text, content: 'Here are a few things I noted during my personal study of Romans 8:3 earlier today:\n\n• The flesh produces death because it relies on our own strength.\n• The Spirit produces life.\n\nI recorded a short voice note on how this played out.'),
      MessagePart(type: MessageType.voice, content: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', durationSeconds: 45),
      MessagePart(type: MessageType.text, content: 'Let me know if any of you have experienced something similar this week!'),
    ], now.subtract(const Duration(minutes: 45)));

    await sendMock(bJohnUid, bJohnName, [
      MessagePart(type: MessageType.text, content: 'Sister Sarah, that voice note was exactly what I needed to hear today.'),
      MessagePart(type: MessageType.text, content: 'One thing I noticed in Romans 8:11 is that the exact same Spirit that raised Jesus from the dead dwells inside us. That completely blows my mind.'),
      MessagePart(type: MessageType.voice, content: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3', durationSeconds: 65),
    ], now.subtract(const Duration(minutes: 30)));

    await sendMock(myUid, myName, [
      MessagePart(type: MessageType.text, content: 'Wow, this is such a rich discussion. John, your point really connects back to Romans 8:2. We have that power accessible to us immediately.'),
      MessagePart(type: MessageType.text, content: 'I spent some time looking up Romans 8:4 and how the righteous requirement of the law is fully met in us.'),
    ], now.subtract(const Duration(minutes: 10)));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intensive Mock data seeded!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.transparent),
            onPressed: _seedMockMessages,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onSelected: (value) {
              if (value == 'clear') {
                _confirmClearChat();
              } else if (value == 'add_members') {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => AddMemberSheet(groupId: widget.group.id),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_members',
                child: Text('Add Members'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Chat'),
              ),
            ],
          ),
        ],
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GroupDetailsScreen(group: widget.group)),
            );
          },
          child: Row(
            children: [
              if (widget.group.photoUrl != null && widget.group.photoUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Container(
                    width: 32,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                      image: DecorationImage(
                        image: NetworkImage(widget.group.photoUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.name,
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 18),
                    ),
                    Row(
                      children: [
                        Text(
                          '${widget.group.members.length} members, 1 online',
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        if (widget.group.pinnedScripture.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Colors.black54, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.group.pinnedScripture,
                              style: const TextStyle(fontFamily: 'Merriweather', fontStyle: FontStyle.italic, color: Colors.black54, fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: StreamBuilder<List<MessageModel>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.black));
                        }
                        if (snapshot.hasError) {
                          return const Center(child: Text('Error loading messages'));
                        }
                        
                        final messages = (snapshot.data ?? [])
                            .where((m) => !m.deletedFor.contains(_currentUserId))
                            .toList();

                        if (messages.isNotEmpty) {
                          final newestId = messages.first.id;
                          if (newestId != _lastNewMessageId) {
                            _lastNewMessageId = newestId;
                            if (messages.first.senderId == _currentUserId) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _jumpToBottom();
                              });
                            }
                          }
                        }

                        if (messages.isEmpty) {
                          return const Center(
                            child: Text('This room is quiet. Share an insight.', style: TextStyle(color: Colors.black54)),
                          );
                        }

                        return Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          thickness: 4.0,
                          radius: const Radius.circular(8),
                          child: ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 48), // Increased bottom padding
                            itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              
                              final message = messages[index];
                              final isMe = message.senderId == _currentUserId;

                              bool showAvatar = true;
                              if (index > 0) {
                                if (messages[index - 1].senderId == message.senderId) {
                                  showAvatar = false;
                                }
                              }

                              return Container(
                                key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
                                child: GestureDetector(
                                  onLongPress: () => _showBubbleMenu(message),
                                  child: _buildMessageBubble(message, isMe, messages, showAvatar),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  if (_showScrollToBottom)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: _smoothScrollToBottom,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: const Center(
                              child: Icon(Icons.arrow_downward, color: Colors.black87, size: 20),
                            ),
                          ),
                        ).animate().fade().scale(),
                      ),
                    ),
                ],
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(MessageModel message) {
    final color = _getAvatarColor(message.senderId);
    final progress = widget.group.readingProgress[message.senderId] ?? 0.0;
    final showPercentage = _showProgressForMessage[message.id] ?? false;

    return GestureDetector(
      onTap: () {
        setState(() {
          _showProgressForMessage[message.id] = !showPercentage;
        });
        
        if (!showPercentage) {
          _progressTimers[message.id]?.cancel();
          _progressTimers[message.id] = Timer(const Duration(milliseconds: 2500), () {
            if (mounted && _showProgressForMessage[message.id] == true) {
              setState(() {
                _showProgressForMessage[message.id] = false;
              });
            }
          });
        } else {
          _progressTimers[message.id]?.cancel();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.group.groupType == 'Bible')
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                backgroundColor: Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          if (showPercentage)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
              alignment: Alignment.center,
              child: Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
              ),
            )
          else
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black12,
              ),
              clipBehavior: Clip.antiAlias,
              child: message.senderPhotoUrl != null && message.senderPhotoUrl!.isNotEmpty
                  ? Image.network(message.senderPhotoUrl!, fit: BoxFit.cover)
                  : const Icon(Icons.person, size: 14, color: Colors.black45),
            ),
        ],
      ),
    );
  }

  
  void _speakMessage(MessageModel message) async {
    String fullText = message.parts
        .where((p) => p.type == MessageType.text)
        .map((p) => p.content)
        .join('\n\n');
    if (fullText.isEmpty) return;

    if (_speakingMessageId == message.id) {
      if (_ttsState == TtsState.playing) {
        await _flutterTts.pause();
        if (mounted) setState(() => _ttsState = TtsState.paused);
      } else if (_ttsState == TtsState.paused) {
        if (mounted) setState(() => _ttsState = TtsState.playing);
        await _flutterTts.speak(fullText);
      } else {
         if (mounted) setState(() => _ttsState = TtsState.playing);
         await _flutterTts.speak(fullText);
      }
    } else {
      await _flutterTts.stop();
      if (mounted) {
        setState(() {
          _speakingMessageId = message.id;
          _ttsState = TtsState.playing;
        });
      }
      
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() { _speakingMessageId = null; _ttsState = TtsState.stopped; });
      });
      _flutterTts.setPauseHandler(() {
        if (mounted) setState(() => _ttsState = TtsState.paused);
      });
      _flutterTts.setContinueHandler(() {
        if (mounted) setState(() => _ttsState = TtsState.playing);
      });
      _flutterTts.setCancelHandler(() {
        if (mounted) setState(() { _speakingMessageId = null; _ttsState = TtsState.stopped; });
      });

      await _flutterTts.speak(fullText);
    }
  }

  void _copyMessage(MessageModel message) {
    String fullText = message.parts
        .where((p) => p.type == MessageType.text)
        .map((p) => p.content)
        .join('\n\n');
    if (fullText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: fullText));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
    }
  }

  void _shareMessage(MessageModel message) {
    String fullText = message.parts
        .where((p) => p.type == MessageType.text)
        .map((p) => p.content)
        .join('\n\n');
    if (fullText.isNotEmpty) {
      Share.share(fullText);
    }
  }

  Widget _buildLightningEffect(String senderId) {
    final color = _getAvatarColor(senderId);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: 4,
          height: constraints.maxHeight,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                child: Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color.withValues(alpha: 0.0), color, color, color.withValues(alpha: 0.0)],
                    ),
                    boxShadow: [BoxShadow(color: color, blurRadius: 6, spreadRadius: 2)],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ).animate(onPlay: (controller) {
                  controller.forward(from: 0).then((_) {
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (mounted) controller.forward(from: 0);
                    });
                  });
                }).slideY(begin: -1, end: (constraints.maxHeight / 60) + 1, duration: 1200.ms, curve: Curves.easeInOut),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildAIThreadMessage(MessageModel message, List<MessageModel> allMessages) {
    List<Widget> threadNodes = [];
    for (var part in message.parts) {
      if (part.type == MessageType.text) {
        final paragraphs = part.content.split(RegExp(r'\n\n|\s{3,}'));
        for (var p in paragraphs) {
          final text = p.trim();
          if (text.isNotEmpty) {
             threadNodes.add(_buildThreadTextNode(text));
          }
        }
      } else if (part.type == MessageType.voice) {
        threadNodes.add(_buildThreadVoiceNode(part, message));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 36.0, top: 12.0, left: 16.0, right: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                message.senderName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _getAvatarColor(message.senderId)),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('h:mm a').format(message.timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: threadNodes.map((node) => _buildThreadRow(node, message.senderId, message.id == _highlightedMessageId)).toList(),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildAvatar(message),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionIcon(Icons.copy_outlined, () => _copyMessage(message)),
                  _buildActionIcon((_speakingMessageId == message.id && _ttsState == TtsState.playing) ? Icons.pause : Icons.volume_up_outlined, () => _speakMessage(message)),
                  _buildActionIcon(message.starredBy.contains(_currentUserId) ? Icons.thumb_up : Icons.thumb_up_outlined, () => _toggleStar(message)),
                  _buildActionIcon(Icons.more_horiz, () => _showBubbleMenu(message)),
                ],
              )
            ],
          )
        ],
      ).animate().fade(duration: 300.ms).slideY(begin: 0.1, curve: Curves.easeOut),
    );
  }

  Widget _buildThreadRow(Widget child, String senderId, bool isHighlighted) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Stack(
              children: [
                Positioned(
                  left: 15,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.black12),
                ),
                if (isHighlighted)
                  Positioned(
                    left: 14,
                    top: 0,
                    bottom: 0,
                    child: _buildLightningEffect(senderId),
                  ),
                Positioned(
                  left: 13,
                  top: 12,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _getAvatarColor(senderId),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0, top: 4.0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichText(String text, TextStyle defaultStyle, TextStyle linkStyle) {
    return RichText(
      text: TextSpan(
        children: ScriptureParser.parseText(
          text: text,
          defaultStyle: defaultStyle,
          linkStyle: linkStyle,
          onReferenceTap: (reference) {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                child: BibleVerseBottomSheet(reference: reference),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThreadTextNode(String text) {
    return _buildRichText(
      text,
      const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
      const TextStyle(fontSize: 15, color: Colors.orange, height: 1.4, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
    );
  }

  Widget _buildThreadVoiceNode(MessagePart part, MessageModel message) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: VoiceMessageBubble(
        audioUrl: part.content,
        isMe: false,
        durationSeconds: part.durationSeconds ?? 0,
        timestamp: message.timestamp,
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Icon(icon, size: 18, color: Colors.black54),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe, List<MessageModel> allMessages, bool showAvatar) {
    if (!isMe && !message.isDeleted) {
      return _buildAIThreadMessage(message, allMessages);
    }

    if (message.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block, size: 14, color: Colors.black54),
                  SizedBox(width: 8),
                  Text('This message was deleted', style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    MessageModel? replyMsg;
    if (message.replyToMessageId != null) {
      try {
        replyMsg = allMessages.firstWhere((m) => m.id == message.replyToMessageId);
      } catch (e) {
        replyMsg = null;
      }
    }

    bool isStandaloneAudio = message.parts.length == 1 && message.parts.first.type == MessageType.voice && replyMsg == null;

    return Padding(
      padding: EdgeInsets.only(bottom: isMe ? 16.0 : 36.0, top: isMe ? 0 : 8.0),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              if (showAvatar) _buildAvatar(message) else const SizedBox(width: 32),
              const SizedBox(width: 8),
              if (message.id == _highlightedMessageId)
                Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: _buildLightningEffect(message.senderId),
                )
            ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                    child: Text(
                      message.senderName,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getAvatarColor(message.senderId)),
                    ),
                  ),

                if (isStandaloneAudio) 
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                        bottomLeft: !isMe ? Radius.zero : const Radius.circular(16),
                      ),
                      border: isMe ? null : Border.all(color: Colors.black12),
                    ),
                    child: VoiceMessageBubble(
                      audioUrl: message.parts.first.content,
                      isMe: isMe,
                      durationSeconds: message.parts.first.durationSeconds ?? 0,
                      timestamp: message.timestamp,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                        bottomLeft: !isMe ? Radius.zero : const Radius.circular(16),
                      ),
                      border: isMe ? null : Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyMsg != null)
                          GestureDetector(
                            onTap: () => _scrollToMessage(replyMsg!.id, allMessages),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.grey[800] : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(left: BorderSide(color: _getAvatarColor(replyMsg.senderId), width: 3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    replyMsg.senderName,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _getAvatarColor(replyMsg.senderId)),
                                  ),
                                  Text(
                                    replyMsg.isDeleted ? 'Deleted message' : (replyMsg.parts.isNotEmpty && replyMsg.parts.first.type == MessageType.text ? replyMsg.parts.first.content : '🎤 Voice Note'),
                                    style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : Colors.black54),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ...message.parts.map((part) {
                          if (part.type == MessageType.text) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: _buildRichText(
                              part.content,
                              TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16),
                              const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            ),
                          );
                        } else if (part.type == MessageType.voice) {
                          return Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: VoiceMessageBubble(
                              audioUrl: part.content,
                              isMe: isMe,
                              durationSeconds: part.durationSeconds ?? 0,
                              timestamp: message.timestamp,
                            ),
                          );
                        } else if (part.type == MessageType.image) {
                            return Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  part.content,
                                  width: 250,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 100),
                                ),
                              ),
                            );
                          } else if (part.type == MessageType.video) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam, color: Colors.redAccent, size: 32),
                                  const SizedBox(width: 8),
                                  Text('Video Attachment', style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
                                ],
                              ),
                            );
                          } else if (part.type == MessageType.document) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.insert_drive_file, color: Colors.orange, size: 32),
                                  const SizedBox(width: 8),
                                  Text('Document', style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
                                ],
                              ),
                            );
                          }
                          return const SizedBox();
                        }),
                      ],
                    ),
                  ),
                
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0, right: 4.0),
                        child: Text('(edited)', style: TextStyle(fontSize: 10, color: Colors.black54)),
                      ),
                    if (message.starredBy.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Icon(Icons.star, size: 14, color: Colors.orange),
                      ),
                  ],
                ),
              ],
            ),
          ),

          if (isMe) ...[
            if (message.id == _highlightedMessageId)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: _buildLightningEffect(message.senderId),
              ),
            const SizedBox(width: 8),
            if (showAvatar) _buildAvatar(message) else const SizedBox(width: 32),
          ]
        ],
      ),
    )).animate().fade(duration: 300.ms).slideY(begin: 0.1, curve: Curves.easeOut);
  }

  Widget _buildInputArea() {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editingMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blueAccent.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Editing Message',
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.blueAccent),
                    onPressed: () => setState(() => _editingMessageId = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          if (_replyToMessageId != null && _replyToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black.withValues(alpha: 0.02),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyToMessage!.senderName}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _replyToMessageId = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // WYSIWYG Editor Block
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Render Draft Parts
                  for (int i = 0; i < _draftParts.length; i++)
                    if (_draftParts[i].type == MessageType.text)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Scrollbar(
                          child: TextField(
                            controller: TextEditingController.fromValue(
                              TextEditingValue(
                                text: _draftParts[i].content,
                                selection: TextSelection.collapsed(offset: _draftParts[i].content.length),
                              ),
                            ),
                            onChanged: (val) {
                              _draftParts[i] = MessagePart(type: MessageType.text, content: val);
                            },
                            maxLines: 4,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: VoiceMessageBubble(
                                audioUrl: _draftParts[i].content,
                                isMe: true,
                                durationSeconds: _draftParts[i].durationSeconds ?? 0,
                                timestamp: DateTime.now(),
                                isDraft: true,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () => _removeDraftPart(i),
                            ),
                          ],
                        ),
                      ),
                  
                  // Active Typing / Recording Row
                  if (_isRecording)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.mic, color: Colors.redAccent)
                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                              .fade(begin: 0.5, end: 1.0, duration: 500.ms),
                          const SizedBox(width: 8),
                          Text(
                            '${(_recordingDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordingDuration % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _cancelRecording,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1)],
                              ),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _saveRecordingToDraft,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1)],
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'Share a thought...',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                            ),
                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          
          // Action Buttons Docked at Bottom Right
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 12, top: 4, left: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isRecording) ...[
                  // Add Attachment Button
                  GestureDetector(
                    onTap: _showAttachmentMenu,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.black87),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _startRecording,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, value, child) {
                      // Also check if any text part has content
                      final hasDrafts = _draftParts.any((p) => p.type == MessageType.voice || (p.type == MessageType.text && p.content.trim().isNotEmpty));
                      final canSend = value.text.trim().isNotEmpty || hasDrafts;
                      return GestureDetector(
                        onTap: canSend ? _sendDraft : null,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: canSend ? AppColors.primary : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.arrow_upward, color: canSend ? Colors.white : Colors.black26),
                        ),
                      );
                    },
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
