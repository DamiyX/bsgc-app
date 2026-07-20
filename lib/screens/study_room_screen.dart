import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/contact_cache_service.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/expandable_rich_text.dart';
import 'group_details_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import 'package:bsgc_app/services/storage_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/scripture_parser.dart';
import '../widgets/bible_verse_bottom_sheet.dart';
import '../widgets/add_member_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

enum TtsState { playing, paused, stopped }


class StudyRoomScreen extends StatefulWidget {
  final GroupModel group;
  final bool showAddMemberPrompt;

  const StudyRoomScreen({super.key, required this.group, this.showAddMemberPrompt = false});

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> with WidgetsBindingObserver {

  final FlutterTts _flutterTts = FlutterTts();
  String? _speakingMessageId;
  TtsState _ttsState = TtsState.stopped;
  List<MessageModel> _cachedMessages = [];
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
  final bool _hasMoreMessages = true;

  void _onScroll() {
    if (_scrollController.hasClients) {
      if (_scrollController.offset > 200 && !_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      } else if (_scrollController.offset <= 200 && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      
      // Load more messages when reaching the top
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore && _hasMoreMessages) {
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

  String _getReplyMessageSummary(MessageModel msg) {
    if (msg.isDeleted) return 'Deleted message';
    if (msg.parts.isEmpty) return '';

    List<String> summaries = [];
    bool hasMultiple = msg.parts.length > 1;
    
    for (var part in msg.parts) {
      if (part.type == MessageType.text) {
        String text = part.content;
        if (hasMultiple) {
            String singleLine = text.replaceAll('\n', ' ').trim();
            if (singleLine.length > 50) {
               singleLine = singleLine.substring(0, 50) + '...';
            }
            summaries.add(singleLine);
        } else {
            summaries.add(text);
        }
      } else if (part.type == MessageType.voice) {
        summaries.add('🎤 Voice Note');
      } else if (part.type == MessageType.image) {
        summaries.add('📷 Photo');
      } else if (part.type == MessageType.video) {
        summaries.add('🎥 Video');
      }
    }
    return summaries.join('\n');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _messagesStream = _chatService.getGroupMessages(widget.group.id, limit: _messageLimit);
    
    _saveActiveRoute();
    
    if (widget.showAddMemberPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddMemberSheet(groupId: widget.group.id),
        );
      });
    }
  }

  Future<void> _saveActiveRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_group_id', widget.group.id);
    await prefs.setInt('active_route_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  void _clearActiveRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_group_id');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveActiveRoute();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearActiveRoute();
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
    if (userId == FirebaseAuth.instance.currentUser?.uid) return AppColors.gradientEnd;
    final List<Color> colors = [
      Colors.blue, Colors.orange, Colors.red, Colors.purple,
      Colors.teal, Colors.pink, Colors.indigo, Colors.amber,
      Colors.cyan, Colors.deepOrange, Colors.lime, Colors.brown
    ];
    int index = widget.group.members.indexOf(userId);
    if (index < 0) {
      int asciiSum = 0;
      for (int i = 0; i < userId.length; i++) {
        asciiSum += userId.codeUnitAt(i);
      }
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
          replyToMessageId: replyId,
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
    final replyId = _replyToMessageId;
    setState(() {
      _replyToMessageId = null;
      _replyToMessage = null;
    });
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
      
      final url = await StorageService.uploadFile(uploadBytes, folder: 'chat_media', extension: extension);
      
      if (url.isNotEmpty) {
        _chatService.sendHybridMessage(
          widget.group.id,
          [MessagePart(type: type, content: url)],
          replyToMessageId: replyId,
        );
        if (_scrollController.hasClients) {
          _jumpToBottom();
        }
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to upload file to Firebase Storage')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
              leading: Icon(Icons.image, color: Colors.blue),
              title: Text('Image'),
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
              leading: Icon(Icons.videocam, color: Colors.red),
              title: Text('Video'),
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
              leading: Icon(Icons.insert_drive_file, color: Colors.orange),
              title: Text('Document'),
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
        title: Text('Delete Message'),
        content: Text(forEveryone ? 'Delete this message for everyone?' : 'Delete this message for yourself?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
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
    if (!isStarred) {
      NotificationService().playActionSound();
    }
    await _chatService.toggleStarMessage(widget.group.id, msg.id, isStarred);
  }

  void _confirmClearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Chat'),
        content: Text('Are you sure you want to clear all messages for yourself? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Clear', style: TextStyle(color: Colors.red))),
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
              leading: Icon(Icons.reply),
              title: Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _setReply(message);
              },
            ),
            ListTile(
              leading: Icon(
                message.starredBy.contains(_currentUserId) ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                color: message.starredBy.contains(_currentUserId) ? Theme.of(context).colorScheme.onSurface : null,
              ),
              title: Text(message.starredBy.contains(_currentUserId) ? 'Unlike' : 'Like'),
              onTap: () {
                Navigator.pop(context);
                _toggleStar(message);
              },
            ),
            if (isMe) ...[
              ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _beginEditMessage(message);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.redAccent),
                title: Text('Delete for Me', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message, false);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Colors.redAccent),
                title: Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
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
              } else if (value == 'theme_gradient') {
                Provider.of<ThemeProvider>(context, listen: false).setChatBubbleTheme(ChatBubbleTheme.gradient);
              } else if (value == 'theme_purple') {
                Provider.of<ThemeProvider>(context, listen: false).setChatBubbleTheme(ChatBubbleTheme.solidPurple);
              } else if (value == 'theme_light_gray') {
                Provider.of<ThemeProvider>(context, listen: false).setChatBubbleTheme(ChatBubbleTheme.lightGray);
              } else if (value == 'theme_dark_gray') {
                Provider.of<ThemeProvider>(context, listen: false).setChatBubbleTheme(ChatBubbleTheme.darkGray);
              } else if (value == 'theme_dark') {
                Provider.of<ThemeProvider>(context, listen: false).setChatBubbleTheme(ChatBubbleTheme.dark);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_members',
                child: Text('Add Members'),
              ),
              const PopupMenuItem(
                value: 'theme_gradient',
                child: Text('Use Gradient Purple Bubbles'),
              ),
              const PopupMenuItem(
                value: 'theme_purple',
                child: Text('Use Solid Purple Bubbles'),
              ),
              const PopupMenuItem(
                value: 'theme_dark_gray',
                child: Text('Use Dark Gray Bubbles'),
              ),
              const PopupMenuItem(
                value: 'theme_light_gray',
                child: Text('Use Light Gray Bubbles'),
              ),
              const PopupMenuItem(
                value: 'theme_dark',
                child: Text('Use Dark Bubbles'),
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
                    padding: EdgeInsets.only(right: 12.0),
                    child: Container(
                      width: 32,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [BoxShadow(color: Theme.of(context).dividerColor, blurRadius: 2, offset: Offset(0, 1))],
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(widget.group.photoUrl!),
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
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.w600, fontSize: 18),
                      ),
                      Row(
                        children: [
                          Text(
                            '${widget.group.members.length} members, 1 online',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12),
                          ),
                          if (widget.group.pinnedScripture.isNotEmpty) ...[
                            SizedBox(width: 8),
                            Text('•', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.group.pinnedScripture,
                                style: TextStyle(fontFamily: 'Merriweather', fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12),
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
        child: Stack(
          children: [
            Positioned.fill(
              child: StreamBuilder<List<MessageModel>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    _cachedMessages = snapshot.data!;
                  }
                  
                  if (snapshot.connectionState == ConnectionState.waiting && _cachedMessages.isEmpty) {
                    return Center(child: CircularProgressIndicator(color: AppColors.gradientEnd));
                  }
                  if (snapshot.hasError && _cachedMessages.isEmpty) {
                    return Center(child: Text('Error loading messages'));
                  }
                  
                  final messages = _cachedMessages
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
                    return Center(
                      child: Text('This room is quiet. Share an insight.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))),
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
                      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 120), // Increased bottom padding for input area
                      itemCount: messages.length + (_isLoadingMore && _hasMoreMessages ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gradientEnd)),
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
                          child: Dismissible(
                            key: Key('dismiss_${message.id}'),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (direction) async {
                              _setReply(message);
                              return false; // Don't actually dismiss
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.only(left: 24.0),
                              child: Icon(Icons.reply, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                            ),
                            child: GestureDetector(
                              onLongPress: () => _showBubbleMenu(message),
                              child: _buildMessageBubble(message, isMe, messages, showAvatar, index),
                            ),
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
                bottom: 100, // Move button above input area
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _smoothScrollToBottom,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                      ),
                      child: Center(
                        child: Icon(Icons.arrow_downward, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87, size: 20),
                      ),
                    ),
                  ).animate().fade().scale(),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.0),
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
                padding: const EdgeInsets.only(top: 32),
                child: _buildInputArea(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(MessageModel message) {
    final color = _getAvatarColor(message.senderId);
    final progress = widget.group.groupType == 'Bible' 
        ? (widget.group.readingProgress[message.senderId] ?? 0.0) 
        : 1.0;
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
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.0,
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (showPercentage)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              alignment: Alignment.center,
              child: Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
            )
          else
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).dividerColor,
              ),
              child: ClipOval(
                child: message.senderPhotoUrl != null && message.senderPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(imageUrl: message.senderPhotoUrl!, fit: BoxFit.cover)
                    : Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
              ),
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
      key: UniqueKey(),
      builder: (context, constraints) {
        return Container(
          width: 4,
          height: constraints.maxHeight,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(),
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

   Widget _buildAIThreadMessage(MessageModel message, List<MessageModel> allMessages, int index) {
    bool isFirstInGroup = index == allMessages.length - 1 || allMessages[index + 1].senderId != message.senderId;
    bool isLastInGroup = index == 0 || allMessages[index - 1].senderId != message.senderId;

    int messagesInGroup = 1;
    if (isLastInGroup) {
      int curr = index + 1;
      while (curr < allMessages.length && allMessages[curr].senderId == message.senderId) {
        messagesInGroup++;
        curr++;
      }
    }

    MessageModel? replyMsg;
    if (message.replyToMessageId != null) {
      try {
        replyMsg = allMessages.firstWhere((m) => m.id == message.replyToMessageId);
      } catch (e) {
        replyMsg = null;
      }
    }

    List<Widget> threadNodes = [];
    if (replyMsg != null) {
       threadNodes.add(
           GestureDetector(
             onTap: () => _scrollToMessage(replyMsg!.id, allMessages),
             child: Container(
                margin: EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(bottom: BorderSide(color: _getAvatarColor(replyMsg.senderId), width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ContactCacheService().getContactName(replyMsg.senderId, replyMsg.senderName),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _getAvatarColor(replyMsg.senderId)),
                    ),
                    Text(
                      _getReplyMessageSummary(replyMsg),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
           )
       );
    }

    if (message.isDeleted) {
      threadNodes.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(message),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ContactCacheService().getContactName(message.senderId, message.senderName),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _getAvatarColor(message.senderId)),
                  ),
                  SizedBox(height: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                        SizedBox(width: 8),
                        Text('Deleted message', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      for (var part in message.parts) {
        if (part.type == MessageType.text) {
          final text = part.content.trim();
          if (text.isNotEmpty) {
             threadNodes.add(_buildThreadTextNode(text));
          }
        } else if (part.type == MessageType.voice) {
          threadNodes.add(_buildThreadVoiceNode(part, message));
        } else if (part.type == MessageType.image) {
          threadNodes.add(
            Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: Colors.black,
                          iconTheme: IconThemeData(color: Colors.white),
                        ),
                        body: Center(
                          child: InteractiveViewer(
                            child: CachedNetworkImage(imageUrl: part.content),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(imageUrl: 
                    part.content,
                    width: 250,
                    height: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) {
                      return Container(
                        width: 250,
                        height: 250,
                        color: Theme.of(context).dividerColor,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorWidget: (context, url, error) => Container(
                      width: 250,
                      height: 250,
                      color: Theme.of(context).dividerColor,
                      child: Icon(Icons.broken_image, size: 50, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              ),
            )
          );
        }
      }
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLastInGroup ? 36.0 : 0.0, 
        top: isFirstInGroup ? 12.0 : 0.0, 
        left: 8.0, 
        right: 16.0
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFirstInGroup)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  ContactCacheService().getContactName(message.senderId, message.senderName),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _getAvatarColor(message.senderId)),
                ),
                SizedBox(width: 8),
                Text(
                  DateFormat('h:mm a').format(message.timestamp),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
              ],
            ),
          if (isFirstInGroup) SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: threadNodes.map((node) => _buildThreadRow(node, message.senderId, message.id == _highlightedMessageId)).toList(),
          ),
          if (isLastInGroup)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildAvatar(message),
                SizedBox(width: 8),
                if (!message.isDeleted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionIcon(Icons.copy_outlined, () => _copyMessage(message)),
                      _buildActionIcon((_speakingMessageId == message.id && _ttsState == TtsState.playing) ? Icons.pause : Icons.volume_up_outlined, () => _speakMessage(message)),
                      _buildActionIcon(message.starredBy.contains(_currentUserId) ? Icons.thumb_up : Icons.thumb_up_alt_outlined, () => _toggleStar(message), message.starredBy.contains(_currentUserId) ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.primary) : Theme.of(context).colorScheme.onSurfaceVariant),
                      _buildActionIcon(Icons.more_horiz, () => _showBubbleMenu(message)),
                    ],
                  )
              ],
            )
        ],
      ),
    );
  }

  Widget _buildThreadRow(Widget child, String senderId, bool isHighlighted) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Stack(
              children: [
                Positioned(
                  left: 15,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Theme.of(context).dividerColor),
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
              padding: EdgeInsets.only(bottom: 16.0, top: 4.0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichText(String text, TextStyle defaultStyle, TextStyle linkStyle) {
    return ExpandableRichText(
      text: text,
      defaultStyle: defaultStyle,
      linkStyle: linkStyle,
      onReferenceTap: (reference) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(horizontal: 16),
            child: BibleVerseBottomSheet(reference: reference),
          ),
        );
      },
    );
  }

  Widget _buildThreadTextNode(String text) {
    return _buildRichText(
      text,
      TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), height: 1.4),
      TextStyle(fontSize: 15, color: Colors.purpleAccent, height: 1.4, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.purpleAccent),
    );
  }

  Widget _buildThreadVoiceNode(MessagePart part, MessageModel message) {
    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: VoiceMessageBubble(
        audioUrl: part.content,
        isMe: false,
        durationSeconds: part.durationSeconds ?? 0,
        timestamp: message.timestamp,
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, VoidCallback onTap, [Color? color]) { color ??= Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Color? _getBubbleColor(BuildContext context, bool isMe) {
    if (!isMe) return Theme.of(context).cardColor;
    final theme = Provider.of<ThemeProvider>(context).chatBubbleTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (theme) {
      case ChatBubbleTheme.solidPurple:
        return AppColors.gradientEnd;
      case ChatBubbleTheme.darkGray:
        return AppColors.primary;
      case ChatBubbleTheme.lightGray:
        return isDark ? Colors.grey[800] : const Color(0xFFF4F4F4);
      case ChatBubbleTheme.dark:
        return isDark ? Colors.grey[800] : Colors.black;
      case ChatBubbleTheme.gradient:
      default:
        return null;
    }
  }

  Color _getBubbleTextColor(BuildContext context, bool isMe) {
    if (!isMe) return Theme.of(context).colorScheme.onSurface;
    final theme = Provider.of<ThemeProvider>(context).chatBubbleTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (theme == ChatBubbleTheme.lightGray && !isDark) {
      return Colors.black87;
    }
    return Colors.white;
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe, List<MessageModel> allMessages, bool showAvatar, int index) {
    if (!isMe) {
      return _buildAIThreadMessage(message, allMessages, index);
    }

    if (message.isDeleted) {
      return Padding(
        padding: EdgeInsets.only(bottom: 16.0),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              if (showAvatar) _buildAvatar(message) else SizedBox(width: 32),
              SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && showAvatar)
                    Padding(
                      padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                      child: Text(
                        ContactCacheService().getContactName(message.senderId, message.senderName),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getAvatarColor(message.senderId)),
                      ),
                    ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                        SizedBox(width: 8),
                        Text('This message was deleted', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isMe) SizedBox(width: 40),
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
      child: Stack(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (message.id == _highlightedMessageId)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: _getAvatarColor(message.senderId).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
              ).animate(onPlay: (controller) {
                controller.forward(from: 0).then((_) {
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (mounted) controller.forward(from: 0);
                  });
                });
              }).fadeIn(duration: 300.ms).fadeOut(duration: 800.ms, delay: 300.ms),
            ),
          IntrinsicHeight(
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              if (showAvatar) _buildAvatar(message) else SizedBox(width: 32),
              SizedBox(width: 8),
              if (message.id == _highlightedMessageId)
                Padding(
                  padding: EdgeInsets.only(right: 4.0),
                  child: _buildLightningEffect(message.senderId),
                )
            ],
            if (isMe && message.id == _highlightedMessageId)
              Padding(
                padding: EdgeInsets.only(right: 8.0, bottom: 8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: _buildLightningEffect(message.senderId),
                ),
              ),
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                    child: Text(
                      ContactCacheService().getContactName(message.senderId, message.senderName),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getAvatarColor(message.senderId)),
                    ),
                  ),

                if (isStandaloneAudio) 
                  Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _getBubbleColor(context, isMe),
                      gradient: (isMe && Provider.of<ThemeProvider>(context).chatBubbleTheme == ChatBubbleTheme.gradient)
                          ? LinearGradient(
                              colors: [AppColors.chatBubbleGradientStart, AppColors.chatBubbleGradientEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isMe ? Radius.zero : Radius.circular(16),
                        bottomLeft: !isMe ? Radius.zero : Radius.circular(16),
                      ),
                      border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
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
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _getBubbleColor(context, isMe),
                      gradient: (isMe && Provider.of<ThemeProvider>(context).chatBubbleTheme == ChatBubbleTheme.gradient)
                          ? LinearGradient(
                              colors: [AppColors.chatBubbleGradientStart, AppColors.chatBubbleGradientEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isMe ? Radius.zero : Radius.circular(16),
                        bottomLeft: !isMe ? Radius.zero : Radius.circular(16),
                      ),
                      border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyMsg != null)
                          GestureDetector(
                            onTap: () => _scrollToMessage(replyMsg!.id, allMessages),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 8),
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isMe ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(bottom: BorderSide(color: _getAvatarColor(replyMsg.senderId), width: 2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ContactCacheService().getContactName(replyMsg.senderId, replyMsg.senderName),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _getAvatarColor(replyMsg.senderId)),
                                  ),
                                  Text(
                                    _getReplyMessageSummary(replyMsg),
                                    style: TextStyle(fontSize: 12, color: isMe ? _getBubbleTextColor(context, isMe).withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ...message.parts.map((part) {
                          if (part.type == MessageType.text) {
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: _buildRichText(
                                part.content,
                                TextStyle(color: _getBubbleTextColor(context, isMe), fontSize: 15),
                                TextStyle(color: Colors.purpleAccent, fontSize: 15, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.purpleAccent),
                              ),
                            );
                        } else if (part.type == MessageType.voice) {
                          return Padding(
                            padding: EdgeInsets.all(2.0),
                            child: VoiceMessageBubble(
                              audioUrl: part.content,
                              isMe: isMe,
                              durationSeconds: part.durationSeconds ?? 0,
                              timestamp: message.timestamp,
                            ),
                          );
                        } else if (part.type == MessageType.image) {
                            return Padding(
                              padding: EdgeInsets.all(4.0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => Scaffold(
                                        backgroundColor: Colors.black,
                                        appBar: AppBar(
                                          backgroundColor: Colors.black,
                                          iconTheme: IconThemeData(color: Colors.white),
                                        ),
                                        body: Center(
                                          child: InteractiveViewer(
                                            child: CachedNetworkImage(imageUrl: part.content),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(imageUrl: 
                                    part.content,
                                    width: 250,
                                    height: 250,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) {
                                      return Container(
                                        width: 250,
                                        height: 250,
                                        color: Colors.white24,
                                        child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                      );
                                    },
                                    errorWidget: (context, url, error) => Container(
                                      width: 250,
                                      height: 250,
                                      color: Colors.white24,
                                      child: Icon(Icons.broken_image, size: 50, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          } else if (part.type == MessageType.video) {
                            return Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam, color: Colors.redAccent, size: 32),
                                  SizedBox(width: 8),
                                  Text('Video Attachment', style: TextStyle(color: _getBubbleTextColor(context, isMe))),
                                ],
                              ),
                            );
                          } else if (part.type == MessageType.document) {
                            return Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.insert_drive_file, color: Colors.orange, size: 32),
                                  SizedBox(width: 8),
                                  Text('Document', style: TextStyle(color: _getBubbleTextColor(context, isMe))),
                                ],
                              ),
                            );
                          }
                          return SizedBox();
                        }),
                      ],
                    ),
                  ),
                
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited)
                      Padding(
                        padding: EdgeInsets.only(top: 4.0, right: 4.0),
                        child: Text('(edited)', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))),
                      ),
                    if (message.starredBy.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(top: 4.0),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('👍', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Text('${message.starredBy.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          if (isMe) ...[
            if (message.id == _highlightedMessageId)
              Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: _buildLightningEffect(message.senderId),
              ),
            SizedBox(width: 8),
            if (showAvatar) _buildAvatar(message) else SizedBox(width: 32),
          ],
        ],
      ),
    ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      margin: EdgeInsets.only(left: 12, right: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(50),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: Offset(0, 0))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editingMessageId != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blueAccent.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Editing Message',
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: Colors.blueAccent),
                    onPressed: () => setState(() => _editingMessageId = null),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),

          if (_replyToMessageId != null && _replyToMessage != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.02),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ContactCacheService().getContactName(_replyToMessage!.senderId, _replyToMessage!.senderName),
                          style: TextStyle(fontSize: 12, color: _getAvatarColor(_replyToMessage!.senderId), fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _getReplyMessageSummary(_replyToMessage!),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16),
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
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Render Draft Parts
                  for (int i = 0; i < _draftParts.length; i++)
                    if (_draftParts[i].type == MessageType.text)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Scrollbar(
                          child: TextField(
                            cursorColor: Theme.of(context).colorScheme.onSurface,
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
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: EdgeInsets.only(bottom: 8.0),
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
                              icon: Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () => _removeDraftPart(i),
                            ),
                          ],
                        ),
                      ),
                  
                  // Active Typing / Recording Row
                  if (_isRecording)
                    Padding(
                      padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.mic, color: Colors.redAccent)
                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                              .fade(begin: 0.5, end: 1.0, duration: 500.ms),
                          SizedBox(width: 8),
                          Text(
                            '${(_recordingDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordingDuration % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Spacer(),
                          GestureDetector(
                            onTap: _cancelRecording,
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Theme.of(context).dividerColor, blurRadius: 4, spreadRadius: 1)],
                              ),
                              child: Icon(Icons.close, color: Colors.redAccent, size: 20),
                            ),
                          ),
                          SizedBox(width: 12),
                          GestureDetector(
                            onTap: _saveRecordingToDraft,
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.gradientStart,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Theme.of(context).dividerColor, blurRadius: 4, spreadRadius: 1)],
                              ),
                              child: Icon(Icons.check, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _showAttachmentMenu,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 8.0, right: 16.0, left: 4.0),
                            child: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), size: 22),
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            child: TextField(
                              cursorColor: Theme.of(context).colorScheme.onSurface,
                              controller: _textController,
                              maxLines: 12,
                              minLines: 1,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
                              decoration: const InputDecoration(
                                hintText: 'Share a thought...',
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _startRecording,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            margin: EdgeInsets.only(bottom: 4, left: 4),
                            child: Icon(Icons.mic, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _textController,
                          builder: (context, value, child) {
                            final hasDrafts = _draftParts.any((p) => p.type == MessageType.voice || (p.type == MessageType.text && p.content.trim().isNotEmpty));
                            final canSend = value.text.trim().isNotEmpty || hasDrafts;
                            return GestureDetector(
                              onTap: canSend ? _sendDraft : null,
                              child: Container(
                                padding: EdgeInsets.all(8),
                                margin: EdgeInsets.only(bottom: 4, left: 4),
                                decoration: BoxDecoration(
                                    color: canSend ? AppColors.gradientEnd : AppColors.gradientEnd.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                child: Icon(Icons.arrow_upward, color: canSend ? Colors.white : AppColors.gradientEnd.withValues(alpha: 0.5)),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



