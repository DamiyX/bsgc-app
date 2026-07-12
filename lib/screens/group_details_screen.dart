import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bsgc_app/services/cloudinary_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import '../models/group_model.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import 'edit_group_screen.dart';

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

  String? _selectedBook;
  int _totalChapters = 0;
  Map<String, dynamic>? _selectedMessage;
  String? _tappedMemberId;
  List<int> _myCompletedChapters = [];

  bool get _isAdmin =>
      widget.group.members.isNotEmpty &&
      widget.group.members.first == _currentUserId;

  final Map<String, int> _bibleChapters = {
    'Genesis': 50,
    'Exodus': 40,
    'Leviticus': 27,
    'Numbers': 36,
    'Deuteronomy': 34,
    'Joshua': 24,
    'Judges': 21,
    'Ruth': 4,
    '1 Samuel': 31,
    '2 Samuel': 24,
    '1 Kings': 22,
    '2 Kings': 25,
    '1 Chronicles': 29,
    '2 Chronicles': 36,
    'Ezra': 10,
    'Nehemiah': 13,
    'Esther': 10,
    'Job': 42,
    'Psalms': 150,
    'Proverbs': 31,
    'Ecclesiastes': 12,
    'Song of Solomon': 8,
    'Isaiah': 66,
    'Jeremiah': 52,
    'Lamentations': 5,
    'Ezekiel': 48,
    'Daniel': 12,
    'Hosea': 14,
    'Joel': 3,
    'Amos': 9,
    'Obadiah': 1,
    'Jonah': 4,
    'Micah': 7,
    'Nahum': 3,
    'Habakkuk': 3,
    'Zephaniah': 3,
    'Haggai': 2,
    'Zechariah': 14,
    'Malachi': 4,
    'Matthew': 28,
    'Mark': 16,
    'Luke': 24,
    'John': 21,
    'Acts': 28,
    'Romans': 16,
    '1 Corinthians': 16,
    '2 Corinthians': 13,
    'Galatians': 6,
    'Ephesians': 6,
    'Philippians': 4,
    'Colossians': 4,
    '1 Thessalonians': 5,
    '2 Thessalonians': 3,
    '1 Timothy': 6,
    '2 Timothy': 4,
    'Titus': 3,
    'Philemon': 1,
    'Hebrews': 13,
    'James': 5,
    '1 Peter': 5,
    '2 Peter': 3,
    '1 John': 5,
    '2 John': 1,
    '3 John': 1,
    'Jude': 1,
    'Revelation': 22,
  };

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _selectedBook = widget.group.studyBook;
    _selectedBook = widget.group.studyBook;
    
    if (widget.group.groupType == 'Topic' && widget.group.startDate != null && widget.group.endDate != null) {
      _totalChapters = widget.group.endDate!.difference(widget.group.startDate!).inDays + 1;
    } else {
      _totalChapters = widget.group.totalChapters;
    }
    
    _myCompletedChapters = List<int>.from(
      widget.group.userCompletedChapters[_currentUserId] ?? [],
    );
  }

  Future<void> _loadMembers() async {
    final members = await _chatService.getGroupMembersProfiles(
      widget.group.members,
    );
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  void _inviteMember() {
    final inviteLink = "https://braidapp.com/join/${widget.group.id}";
    final message =
        "Hey! Join my Bible study group '${widget.group.name}' on Braid!\n\nTap here to join: $inviteLink";
    Share.share(message);
  }

  void _toggleChapter(int chapter) async {
    setState(() {
      if (_myCompletedChapters.contains(chapter)) {
        _myCompletedChapters.remove(chapter);
      } else {
        _myCompletedChapters.add(chapter);
      }

      double newProgress = _totalChapters > 0
          ? (_myCompletedChapters.length / _totalChapters)
          : 0.0;
      widget.group.readingProgress[_currentUserId] = newProgress;
      widget.group.userCompletedChapters[_currentUserId] = _myCompletedChapters;
    });

    double finalProgress = _totalChapters > 0
        ? (_myCompletedChapters.length / _totalChapters)
        : 0.0;
    await _chatService.updateGroupStudyProgress(
      widget.group.id,
      _selectedBook ?? '',
      _totalChapters,
      _myCompletedChapters,
      finalProgress,
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
      0.0,
    );
  }

  void _editGroupDetails() async {
    if (!_isAdmin) return;

    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditGroupScreen(group: widget.group, chatService: _chatService),
      ),
    );

    if (updated == true) {
      setState(() {});
    }
  }

  void _changeGroupImage() async {
    if (!_isAdmin) return;

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploading image...')));

      try {
        var bytes = await image.readAsBytes();

        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 500,
          minHeight: 500,
          quality: 70,
        );
        bytes = compressed;

        final newUrl = await CloudinaryService.uploadFile(bytes);
        if (newUrl == null) {
          throw Exception('Cloudinary configuration missing or upload failed');
        }

        await _chatService.editGroup(
          widget.group.id,
          widget.group.name,
          widget.group.pinnedScripture,
          description: widget.group.description,
          photoUrl: newUrl,
        );
        setState(() {
          widget.group.photoUrl = newUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image updated successfully!')),
          );
        }
      } on TimeoutException {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Upload timed out. Please check your internet connection.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to update image: $e')));
        }
      }
    }
  }

  Future<void> _extendGroup() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extend Group?'),
        content: const Text(
          'Are you sure you want to extend this group by 30 days? You can only extend a group up to 3 times.',
        ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gradientEnd,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Extend'),
            ),
          ],
      ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Extending...')));
      try {
        bool success = await _chatService.extendGroupDuration(
          widget.group.id,
          const Duration(days: 30),
        );
        if (success && mounted) {
          setState(() {
            // Updating local count for immediate UI feedback
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group extended successfully!')),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum extensions reached.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.leaveGroup(widget.group.id);
      if (mounted) {
        Navigator.popUntil(
          context,
          (route) => route.isFirst,
        ); // Return to Main Hall
      }
    }
  }

  Color _getAvatarColor(String userId) {
    if (userId == FirebaseAuth.instance.currentUser?.uid) return AppColors.gradientEnd;
    final List<Color> colors = [
      Colors.blue,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.deepOrange,
      Colors.lime,
      Colors.brown,
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

  Widget _buildGroupImage() {
    if (widget.group.photoUrl != null && widget.group.photoUrl!.isNotEmpty) {
      return Image.network(
        widget.group.photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _fallbackGroupGraphic();
        },
      );
    }

    return _fallbackGroupGraphic();
  }

  Widget _fallbackGroupGraphic() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          widget.group.name.isNotEmpty
              ? widget.group.name[0].toUpperCase()
              : 'G',
          style: const TextStyle(
            fontSize: 80,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAdmin && widget.group.extensionCount < 3) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gradientEnd,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _extendGroup,
                  icon: const Icon(Icons.update),
                  label: Text(
                    'Extend Group Duration (${3 - widget.group.extensionCount} remaining)',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _leaveGroup,
                icon: const Icon(Icons.exit_to_app),
                label: const Text(
                  'Leave Group',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: const IconThemeData(color: Colors.black87),
                  systemOverlayStyle: const SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: Brightness.dark,
                    statusBarBrightness: Brightness.light,
                  ),
                  flexibleSpace: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final top = constraints.biggest.height;
                          final isCollapsed =
                              top <=
                              kToolbarHeight +
                                  MediaQuery.of(context).padding.top +
                                  20;

                          return FlexibleSpaceBar(
                            titlePadding: const EdgeInsets.only(
                              left: 48,
                              bottom: 16,
                              right: 16,
                            ),
                            title: isCollapsed
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipOval(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: _buildGroupImage(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.group.name,
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                            background: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.only(
                                top: 100,
                                left: 24,
                                right: 24,
                                bottom: 16,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: SizedBox(
                                          width: 100,
                                          height: 100,
                                          child: _buildGroupImage(),
                                        ),
                                      ),
                                      if (_isAdmin)
                                        Positioned(
                                          bottom: -4,
                                          right: -4,
                                          child: IconButton(
                                            icon: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: AppColors.gradientEnd,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.edit,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                            onPressed: _changeGroupImage,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.group.name,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (widget
                                            .group
                                            .description
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            widget.group.description,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                  ),
                  actions: [
                    if (_isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              size: 20,
                              color: Colors.black87,
                            ),
                          ),
                          onPressed: _editGroupDetails,
                          tooltip: 'Edit Details',
                        ),
                      ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.group.pinnedScripture.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: Colors.deepOrange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.group.pinnedScripture,
                                    style: const TextStyle(
                                      fontFamily: 'Merriweather',
                                      fontStyle: FontStyle.italic,
                                      color: Colors.black87,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],

                        // Progress Section
                        GestureDetector(
                          onTap: () => setState(
                            () => _isProgressExpanded = !_isProgressExpanded,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'My Progress',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Icon(
                                _isProgressExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_isProgressExpanded) ...[
                          // Book Selection or Topic Display
                          if (widget.group.groupType == 'Topic')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lightbulb_outline, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.group.topic ?? 'Topic',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => Container(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.info_outline, size: 48, color: AppColors.gradientStart),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Book changes restricted',
                                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'You can only make these changes when you extend the group chat.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: AbsorbPointer(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
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
                              ),
                            ),
                          const SizedBox(height: 16),

                          if (widget.group.groupType == 'Topic' || _selectedBook != null) ...[
                            Text(
                              widget.group.groupType == 'Topic' ? 'Days' : 'Chapters',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
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
                                physics: const BouncingScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 7,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1,
                                    ),
                                itemCount: _totalChapters,
                                itemBuilder: (context, index) {
                                  final chapter = index + 1;
                                  final isCompleted = _myCompletedChapters
                                      .contains(chapter);
                                  return GestureDetector(
                                    onTap: widget.group.groupType == 'Topic' ? null : () => _toggleChapter(chapter),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? _getAvatarColor(_currentUserId)
                                            : Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$chapter',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isCompleted
                                              ? Colors.white
                                              : Colors.black87,
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

                        // Group Members Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Group Members',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _inviteMember,
                              icon: const Icon(
                                Icons.person_add,
                                size: 18,
                                color: AppColors.gradientEnd,
                              ),
                              label: const Text(
                                'Add',
                                style: TextStyle(color: AppColors.gradientEnd),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _members.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 24),
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            final uid =
                                member['uid']?.toString() ??
                                widget.group.members[index];
                            final name =
                                member['displayName']?.toString() ?? 'Unknown';
                            final photo = member['photoURL']?.toString();
                            final progress =
                                widget.group.readingProgress[uid] ?? 0.0;
                            final isMe = uid == _currentUserId;
                            final isAdmin = uid == widget.group.members.first;

                            final avatarColor = _getAvatarColor(uid);
                            final initial = name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?';

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _tappedMemberId = (_tappedMemberId == uid)
                                      ? null
                                      : uid;
                                });
                              },
                              child: Row(
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 3,
                                          backgroundColor: Colors.black12,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                avatarColor,
                                              ),
                                        ),
                                      ),
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: avatarColor,
                                        backgroundImage:
                                            (_tappedMemberId != uid &&
                                                photo != null &&
                                                photo.isNotEmpty)
                                            ? NetworkImage(photo)
                                            : null,
                                        child: _tappedMemberId == uid
                                            ? Text(
                                                '${(progress * 100).toInt()}%',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : ((photo == null || photo.isEmpty)
                                                  ? Text(
                                                      initial,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    )
                                                  : null),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              isMe ? '$name (You)' : name,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: isMe
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            if (isAdmin) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.gradientEnd
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Admin',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.gradientEnd,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
