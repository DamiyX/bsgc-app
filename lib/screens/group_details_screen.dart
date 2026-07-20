import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bsgc_app/services/storage_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import '../models/group_model.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../services/contact_cache_service.dart';
import 'edit_group_screen.dart';
import '../services/contact_cache_service.dart';

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
      _group.members.isNotEmpty &&
      _group.members.first == _currentUserId;

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

  late GroupModel _group;
  StreamSubscription<DocumentSnapshot>? _groupSub;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    
    _groupSub = FirebaseFirestore.instance.collection('groups').doc(_group.id).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final newGroup = GroupModel.fromFirestore(snap);
        bool membersChanged = newGroup.members.length != _group.members.length;
        setState(() {
          _group = newGroup;
        });
        if (membersChanged) {
          _loadMembers();
        }
      }
    });

    _loadMembers();
    _selectedBook = _group.studyBook;
    _selectedBook = _group.studyBook;
    
    if (_group.groupType == 'Topic' && _group.startDate != null && _group.endDate != null) {
      _totalChapters = _group.endDate!.difference(_group.startDate!).inDays + 1;
    } else {
      _totalChapters = _group.totalChapters;
    }
    
    _myCompletedChapters = List<int>.from(
      _group.userCompletedChapters[_currentUserId] ?? [],
    );
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await _chatService.getGroupMembersProfiles(
      _group.members,
    );
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  void _inviteMember() {
    final inviteLink = "https://braidapp.com/join/${_group.id}";
    final message =
        "Hey! Join my Bible study group '${_group.name}' on Braid!\n\nTap here to join: $inviteLink";
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
      _group.readingProgress[_currentUserId] = newProgress;
      _group.userCompletedChapters[_currentUserId] = _myCompletedChapters;
    });

    double finalProgress = _totalChapters > 0
        ? (_myCompletedChapters.length / _totalChapters)
        : 0.0;
    await _chatService.updateGroupStudyProgress(
      _group.id,
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

      _group.readingProgress[_currentUserId] = 0.0;
      _group.userCompletedChapters[_currentUserId] = [];
    });
    await _chatService.updateGroupStudyProgress(
      _group.id,
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
            EditGroupScreen(group: _group, chatService: _chatService),
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

        final newUrl = await StorageService.uploadFile(bytes, folder: 'groups');
        if (newUrl.isEmpty) {
          throw Exception('Firebase Storage upload failed');
        }

        await _chatService.editGroup(
          _group.id,
          _group.name,
          _group.pinnedScripture,
          description: _group.description,
          photoUrl: newUrl,
        );
        setState(() {
          _group.photoUrl = newUrl;
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
        title: Text('Extend Group?'),
        content: Text(
          'Are you sure you want to extend this group by 30 days? You can only extend a group up to 3 times.',
        ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gradientEnd,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Extend'),
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
          _group.id,
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
        title: Text('Leave Group?'),
        content: Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.leaveGroup(_group.id);
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
    int index = _group.members.indexOf(userId);
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
    if (_group.photoUrl != null && _group.photoUrl!.isNotEmpty) {
      return CachedNetworkImage(imageUrl: 
        _group.photoUrl!,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) {
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
          _group.name.isNotEmpty
              ? _group.name[0].toUpperCase()
              : 'G',
          style: TextStyle(
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAdmin && _group.extensionCount < 3) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gradientEnd,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _extendGroup,
                  icon: Icon(Icons.update),
                  label: Text(
                    'Extend Group Duration (${3 - _group.extensionCount} remaining)',
                  ),
                ),
                SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(color: Colors.redAccent),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _leaveGroup,
                icon: Icon(Icons.exit_to_app),
                label: Text(
                  'Leave Group',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),                  flexibleSpace: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final top = constraints.biggest.height;
                          final isCollapsed =
                              top <=
                              kToolbarHeight +
                                  MediaQuery.of(context).padding.top +
                                  20;

                          return FlexibleSpaceBar(
                            titlePadding: EdgeInsets.only(
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
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _group.name,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
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
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: EdgeInsets.only(
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
                                              padding: EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: AppColors.gradientEnd,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
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
                                  SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _group.name,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (widget
                                            .group
                                            .description
                                            .isNotEmpty) ...[
                                          SizedBox(height: 6),
                                          Text(
                                            _group.description,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
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
                        padding: EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.edit,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
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
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_group.pinnedScripture.isNotEmpty) ...[
                          Container(
                            padding: EdgeInsets.all(12),
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
                                Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: Colors.deepOrange,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _group.pinnedScripture,
                                    style: TextStyle(
                                      fontFamily: 'Merriweather',
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 32),
                        ],

                        // Progress Section
                        GestureDetector(
                          onTap: () => setState(
                            () => _isProgressExpanded = !_isProgressExpanded,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'My Progress',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                                ),
                              ),
                              Icon(
                                _isProgressExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        if (_isProgressExpanded) ...[
                          // Book Selection or Topic Display
                          if (_group.groupType == 'Topic')
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => Container(
                                    padding: EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.info_outline, size: 48, color: AppColors.gradientStart),
                                        SizedBox(height: 16),
                                        Text(
                                          'Topic changes restricted',
                                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'You can only make these changes when you extend the group chat.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: AbsorbPointer(
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).dividerColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.lightbulb_outline, color: AppColors.primary),
                                      SizedBox(width: 8),
                                      Text(
                                        _group.topic ?? 'Topic',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => Container(
                                    padding: EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.info_outline, size: 48, color: AppColors.gradientStart),
                                        SizedBox(height: 16),
                                        Text(
                                          'Book changes restricted',
                                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'You can only make these changes when you extend the group chat.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: AbsorbPointer(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).dividerColor),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      hint: Text('Select a Book to Study'),
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
                          SizedBox(height: 16),

                          if (_group.groupType == 'Topic' || _selectedBook != null) ...[
                            Text(
                              _group.groupType == 'Topic' ? 'Days' : 'Chapters',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 8),
                            Container(
                              height: 120, // fixed height for chapter grid
                              decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).dividerColor),
                                    borderRadius: BorderRadius.circular(12),
                                    color: Theme.of(context).cardColor,
                                  ),
                              child: GridView.builder(
                                padding: EdgeInsets.all(8),
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
                                    onTap: _group.groupType == 'Topic' ? null : () => _toggleChapter(chapter),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? _getAvatarColor(_currentUserId)
                                            : Theme.of(context).colorScheme.onSurface.withValues(
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
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: 24),
                          ],
                        ],

                        // Group Members Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Group Members',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _inviteMember,
                              icon: Icon(
                                Icons.person_add,
                                size: 18,
                                color: AppColors.gradientEnd,
                              ),
                              label: Text(
                                'Add',
                                style: TextStyle(color: AppColors.gradientEnd),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),

                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _members.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: 24),
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            final uid =
                                member['uid']?.toString() ??
                                _group.members[index];
                            final googleName =
                                ContactCacheService().getContactName(member['uid'], member['displayName']?.toString() ?? 'Unknown');
                            final name = ContactCacheService().getContactName(uid, googleName);
                            final photo = member['photoURL']?.toString();
                            final progress =
                                _group.readingProgress[uid] ?? 0.0;
                            final isMe = uid == _currentUserId;
                            final isAdmin = uid == _group.members.first;

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
                                          backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
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
                                            ? CachedNetworkImageProvider(photo)
                                            : null,
                                        child: _tappedMemberId == uid
                                            ? Text(
                                                '${(progress * 100).toInt()}%',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : ((photo == null || photo.isEmpty)
                                                  ? Text(
                                                      initial,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    )
                                                  : null),
                                      ),
                                    ],
                                  ),
                                  SizedBox(width: 16),
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
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                                              ),
                                            ),
                                            if (isAdmin) ...[
                                              SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.gradientEnd
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
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

