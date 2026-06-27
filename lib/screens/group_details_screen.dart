import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import '../models/group_model.dart';
import '../services/chat_service.dart';
import '../theme.dart';

class GroupDetailsScreen extends StatefulWidget {
  final GroupModel group;

  const GroupDetailsScreen({super.key, required this.group});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final ChatService _chatService = ChatService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isProgressExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _selectedBook = widget.group.studyBook;
    _totalChapters = widget.group.totalChapters;
    _myCompletedChapters = List<int>.from(widget.group.userCompletedChapters[_currentUserId] ?? []);
  }

  String? _selectedBook;
  int _totalChapters = 0;
  List<int> _myCompletedChapters = [];

  final Map<String, int> _bibleChapters = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36, 'Deuteronomy': 34,
    'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31, '2 Samuel': 24,
    '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29, '2 Chronicles': 36, 'Ezra': 10,
    'Nehemiah': 13, 'Esther': 10, 'Job': 42, 'Psalms': 150, 'Proverbs': 31,
    'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66, 'Jeremiah': 52,
    'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12, 'Hosea': 14, 'Joel': 3,
    'Amos': 9, 'Obadiah': 1, 'Jonah': 4, 'Micah': 7, 'Nahum': 3, 'Habakkuk': 3,
    'Zephaniah': 3, 'Haggai': 2, 'Zechariah': 14, 'Malachi': 4, 'Matthew': 28,
    'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28, 'Romans': 16, '1 Corinthians': 16,
    '2 Corinthians': 13, 'Galatians': 6, 'Ephesians': 6, 'Philippians': 4,
    'Colossians': 4, '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6,
    '2 Timothy': 4, 'Titus': 3, 'Philemon': 1, 'Hebrews': 13, 'James': 5,
    '1 Peter': 5, '2 Peter': 3, '1 John': 5, '2 John': 1, '3 John': 1,
    'Jude': 1, 'Revelation': 22
  };

  Future<void> _loadMembers() async {
    final members = await _chatService.getGroupMembersProfiles(widget.group.members);
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  void _inviteMember() {
    final inviteLink = "https://bsgc.app/join/${widget.group.id}";
    final message = "Hey! Join my Bible study group '${widget.group.name}' on BSGC App.\n\nTap here to join: $inviteLink";
    Share.share(message);
  }

  void _toggleChapter(int chapter) async {
    setState(() {
      if (_myCompletedChapters.contains(chapter)) {
        _myCompletedChapters.remove(chapter);
      } else {
        _myCompletedChapters.add(chapter);
      }
      
      double newProgress = _totalChapters > 0 ? (_myCompletedChapters.length / _totalChapters) : 0.0;
      widget.group.readingProgress[_currentUserId] = newProgress;
      widget.group.userCompletedChapters[_currentUserId] = _myCompletedChapters;
    });

    double finalProgress = _totalChapters > 0 ? (_myCompletedChapters.length / _totalChapters) : 0.0;
    await _chatService.updateGroupStudyProgress(
      widget.group.id, 
      _selectedBook ?? '', 
      _totalChapters, 
      _myCompletedChapters, 
      finalProgress
    );
  }

  void _onBookSelected(String? bookName) async {
    if (bookName == null) return;
    setState(() {
      _selectedBook = bookName;
      _totalChapters = _bibleChapters[bookName]!;
      _myCompletedChapters.clear();
      
      widget.group.readingProgress[_currentUserId] = 0.0;
      widget.group.userCompletedChapters[_currentUserId] = [];
    });
    await _chatService.updateGroupStudyProgress(
      widget.group.id, 
      _selectedBook!, 
      _totalChapters, 
      [], 
      0.0
    );
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: widget.group.name);
    final descController = TextEditingController(text: widget.group.description);
    String currentPhotoUrl = widget.group.photoUrl ?? '';
    
    final unsplashKeywords = ['bible', 'church', 'prayer', 'worship', 'nature', 'community', 'cross'];
    final random = Random();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Group'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentPhotoUrl.isNotEmpty) ...[
                    Container(
                      width: 100,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(currentPhotoUrl),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            // In a real app we'd upload this to Firebase Storage.
                            // For prototype, if it's a local file we might have issues sharing it without uploading.
                            // But let's just pretend we use the local path for now or a mock URL.
                            // Actually, just set the path. But Image.network won't work for local paths.
                            // So let's just show a snackbar saying "Uploading..." and then use a mock URL.
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulating upload...')));
                            setState(() {
                              currentPhotoUrl = 'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=400&q=80';
                            });
                          }
                        },
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Gallery'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final keyword = unsplashKeywords[random.nextInt(unsplashKeywords.length)];
                          setState(() {
                            // Using random string to bust cache
                            currentPhotoUrl = 'https://source.unsplash.com/400x600/?$keyword&${random.nextInt(1000)}';
                          });
                        },
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Random'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Group Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
              ),
              TextButton(
                onPressed: () async {
                  await _chatService.editGroup(
                    widget.group.id, 
                    nameController.text.trim(), 
                    '', // removed pinned scripture
                    description: descController.text.trim(),
                    photoUrl: currentPhotoUrl,
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    Navigator.pop(context); // Go back to StudyRoom to refresh
                  }
                },
                child: const Text('Save', style: TextStyle(color: Colors.black87)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.leaveGroup(widget.group.id);
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst); // Return to Main Hall
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Group Roster',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20, color: Colors.black87),
            onPressed: _showEditDialog,
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, size: 20, color: Colors.redAccent),
            onPressed: _leaveGroup,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.black87))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.group.photoUrl != null && widget.group.photoUrl!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: Container(
                            width: 72,
                            height: 108,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
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
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                            if (widget.group.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.group.description,
                                style: const TextStyle(fontSize: 14, color: Colors.black54),
                              ),
                            ],
                            if (widget.group.pinnedScripture.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                widget.group.pinnedScripture,
                                style: const TextStyle(
                                  fontFamily: 'Merriweather',
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black54,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () => setState(() => _isProgressExpanded = !_isProgressExpanded),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My Progress',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black87),
                        ),
                        Icon(_isProgressExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isProgressExpanded) ...[
                    // Book Selection
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Select a Book to Study'),
                        value: _selectedBook,
                        items: _bibleChapters.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.key),
                          );
                        }).toList(),
                        onChanged: _onBookSelected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_selectedBook != null) ...[
                    const Text('Chapters', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      height: 120, // fixed height for chapter grid
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: _totalChapters,
                        itemBuilder: (context, index) {
                          final chapter = index + 1;
                          final isCompleted = _myCompletedChapters.contains(chapter);
                          return GestureDetector(
                            onTap: () => _toggleChapter(chapter),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isCompleted ? Colors.green : Colors.black.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$chapter',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Group Members',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black87),
                      ),
                      TextButton.icon(
                        onPressed: _inviteMember,
                        icon: const Icon(Icons.person_add, size: 18, color: AppColors.primary),
                        label: const Text('Add', style: TextStyle(color: AppColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 24),
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final uid = member['uid'] as String;
                        final name = member['displayName'] as String;
                        final photo = member['photoURL'] as String?;
                        final progress = widget.group.readingProgress[uid] ?? 0.0;
                        final isMe = uid == _currentUserId;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 3,
                                        backgroundColor: Colors.black12,
                                        valueColor: AlwaysStoppedAnimation<Color>(isMe ? Colors.green : Colors.blueAccent),
                                      ),
                                    ),
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.black12,
                                      backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                                      child: (photo == null || photo.isEmpty) ? const Icon(Icons.person, size: 16, color: Colors.black45) : null,
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isMe ? '$name (You)' : name,
                                        style: TextStyle(
                                          fontSize: 16, 
                                          fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
                                          color: Colors.black87
                                        ),
                                      ),
                                      Text(
                                        'Completed: ${(progress * 100).toInt()}%',
                                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
