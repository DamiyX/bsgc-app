import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../models/group_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bsgc_app/services/cloudinary_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'study_room_screen.dart';
import 'create_group_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets/insights_row.dart';
import 'package:intl/intl.dart';

import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../services/notification_service.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'create_note_screen.dart';

class MainHallScreen extends StatelessWidget {
  const MainHallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final chatService = ChatService();

    // Initialize push notifications when user enters the main hall
    NotificationService().init();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/icon2.png', height: 44)),
            const SizedBox(width: 8),
            const Text(
              'Braid',
              style: TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.w600, fontSize: 26, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person, size: 20, color: Colors.grey)
                        : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.black87),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<GroupModel>>(
          stream: chatService.getUserGroups(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.gradientEnd),
              );
            }
            if (snapshot.hasError) {
              return const Center(child: Text('Error loading groups'));
            }
            final groups = snapshot.data ?? [];

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: InsightsRow()),
                if (groups.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        'Study groups',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                if (groups.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'You are not in any groups yet.',
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final group = groups[index];
                      return Column(
                        children: [
                          InkWell(
                                onTap: () {
                                  chatService.resetUnreadCount(group.id);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          StudyRoomScreen(group: group),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 96,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                          image:
                                              group.photoUrl != null &&
                                                  group.photoUrl!.isNotEmpty
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                    group.photoUrl!,
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child:
                                            group.photoUrl == null ||
                                                group.photoUrl!.isEmpty
                                            ? const Icon(
                                                Icons.book,
                                                size: 28,
                                                color: Colors.black45,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              group.name,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _buildGroupSubtitle(group),
                                          ],
                                        ),
                                      ),
                                      _buildTrailingInfo(group, index),
                                    ],
                                  ),
                                ),
                              )
                              .animate()
                              .fade(duration: 300.ms, delay: (index * 50).ms)
                              .slideY(
                                begin: 0.1,
                                duration: 300.ms,
                                curve: Curves.easeOutQuad,
                              ),
                          if (index < groups.length - 1)
                            const Divider(color: Colors.black12, height: 1),
                        ],
                      );
                    }, childCount: groups.length),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: AppColors.gradientEnd,
        foregroundColor: Colors.white,
        activeBackgroundColor: Colors.redAccent,
        activeForegroundColor: Colors.white,
        visible: true,
        curve: Curves.bounceIn,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.description, color: Colors.white),
            backgroundColor: AppColors.textMain,
            label: 'Create Note',
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateNoteScreen()),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.group_add, color: Colors.white),
            backgroundColor: AppColors.gradientEnd,
            label: 'Create Study Group',
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateGroupScreen(chatService: chatService),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showProfileOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Change Profile Picture'),
              onTap: () async {
                Navigator.pop(ctx);
                await _changeProfilePicture(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeProfilePicture(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading new profile picture...')),
      );
    }

    try {
      final bytes = await pickedFile.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 400,
        minHeight: 400,
        quality: 70,
      );

      final url = await CloudinaryService.uploadFile(compressed);
      if (url == null) {
        throw Exception('Cloudinary configuration missing or upload failed');
      }

      await user.updatePhotoURL(url);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'photoURL': url},
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update picture: $e')));
      }
    }
  }

  Widget _buildGroupSubtitle(GroupModel group) {
    if (group.startDate == null || group.endDate == null) {
      if (group.groupType == 'Bible') {
        return Text(
          'Book: ${group.studyBook ?? 'None'}',
          style: const TextStyle(color: Colors.black54),
        );
      } else {
        return Text(
          'Topic: ${group.topic ?? 'None'}',
          style: const TextStyle(color: Colors.black54),
        );
      }
    }

    final now = DateTime.now();
    final start = group.startDate!;
    final end = group.endDate!;

    int totalDays = end.difference(start).inDays + 1;
    int currentDay = now.difference(start).inDays + 1;

    if (currentDay < 1) currentDay = 0;
    if (currentDay > totalDays) currentDay = totalDays;

    String subtitleText = 'Day $currentDay of $totalDays • ';
    if (group.groupType == 'Bible') {
      subtitleText += 'Book: ${group.studyBook ?? 'None'}';
    } else {
      subtitleText += 'Topic: ${group.topic ?? 'None'}';
    }

    return Text(
      subtitleText,
      style: const TextStyle(fontSize: 13, color: Colors.black54),
    );
  }

  Widget _buildTrailingInfo(GroupModel group, int index) {
    final user = FirebaseAuth.instance.currentUser;
    int unreadCount = user != null ? (group.unreadCounts[user.uid] ?? 0) : 0;

    // --- SIMULATION LOGIC ---
    // If the group has no unread messages, artificially simulate some for testing.
    if (unreadCount == 0) {
      if (index % 3 == 0) {
        unreadCount = 5;
      } else if (index % 3 == 1)
        unreadCount = 1;
    }
    // ------------------------

    final hasUnread = unreadCount > 0;

    String timeText = '';
    if (group.lastMessageTime != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDate = DateTime(
        group.lastMessageTime!.year,
        group.lastMessageTime!.month,
        group.lastMessageTime!.day,
      );

      if (msgDate == today) {
        timeText = DateFormat('h:mm a').format(group.lastMessageTime!);
      } else if (msgDate == yesterday) {
        timeText = 'Yesterday';
      } else {
        timeText = DateFormat('MMM d').format(group.lastMessageTime!);
      }
    }

    // --- SIMULATION LOGIC ---
    if (timeText.isEmpty) {
      if (index % 3 == 0) {
        timeText = '10:45 AM';
      } else if (index % 3 == 1)
        timeText = 'Yesterday';
      else
        timeText = 'Oct 12';
    }
    // ------------------------

    if (timeText.isEmpty && !hasUnread) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timeText.isNotEmpty)
            Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                color: hasUnread ? AppColors.gradientEnd : Colors.black54,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.gradientEnd,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _seedMockData(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    // Tiny valid base64 wav header so it doesn't crash AudioPlayer
    const dummyAudio =
        'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

    final avatars = {
      'mock_user_1':
          'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150&q=80', // Woman profile
      'mock_user_2':
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=150&q=80', // Man profile
      'mock_user_3':
          'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&q=80', // Woman profile
      'mock_user_4':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&q=80', // Woman profile
      user.uid: user.photoURL,
    };

    final mockNames = {
      'mock_user_1': 'Grace',
      'mock_user_2': 'James',
      'mock_user_3': 'Love',
      'mock_user_4': 'Dammy',
    };

    for (var entry in mockNames.entries) {
      batch.set(firestore.collection('users').doc(entry.key), {
        'uid': entry.key,
        'displayName': entry.value,
        'photoURL': avatars[entry.key],
      });
    }

    // Group 1
    final g1Ref = firestore.collection('groups').doc('bible_study_group');
    batch.set(g1Ref, {
      'name': "Men's Monday Fellowship",
      'photoUrl':
          'https://images.unsplash.com/photo-1544411047-c45ba52fb7a0?w=400&q=80', // Bible/reading aesthetic
      'members': [user.uid, 'mock_user_1', 'mock_user_2'],
      'readingProgress': {
        user.uid: 0.0,
        'mock_user_1': 0.3,
        'mock_user_2': 0.8,
      },
      'pinnedScripture': 'Proverbs 27:17',
      'groupType': 'Bible',
      'studyBook': 'Proverbs',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final g1Msgs = [
      {
        'id': 'mock_user_1',
        'name': 'Jack',
        'parts': [
          {'type': 'text', 'content': 'Welcome to the Monday Fellowship!'},
        ],
      },
      {
        'id': 'mock_user_2',
        'name': 'James',
        'parts': [
          {
            'type': 'text',
            'content':
                'Looking forward to our study tonight. Who is leading the prayer?',
          },
        ],
      },
      {
        'id': 'mock_user_1',
        'name': 'Jack',
        'parts': [
          {
            'type': 'text',
            'content': 'I will be leading the opening prayer today.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {
            'type': 'text',
            'content': 'Great! I have some questions on the previous chapter.',
          },
        ],
      },
      {
        'id': 'mock_user_1',
        'name': 'Jack',
        'parts': [
          {'type': 'text', 'content': 'Sure, drop them here.'},
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 15},
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {
            'type': 'text',
            'content': 'I was wondering about the context of verse 10.',
          },
        ],
      },
      {
        'id': 'mock_user_2',
        'name': 'James',
        'parts': [
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 42},
          {
            'type': 'text',
            'content': 'I tried to explain it in this voice note.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {
            'type': 'text',
            'content': 'Wow, that makes so much sense now. Thank you, James!',
          },
        ],
      },
      {
        'id': 'mock_user_1',
        'name': 'Jack',
        'parts': [
          {'type': 'text', 'content': 'Exactly! James nailed it.'},
        ],
      },
      {
        'id': 'mock_user_2',
        'name': 'James',
        'parts': [
          {'type': 'text', 'content': 'Glory to God.'},
        ],
      },
      {
        'id': 'mock_user_1',
        'name': 'Jack',
        'parts': [
          {
            'type': 'text',
            'content': 'Let us prepare for the evening session now.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {'type': 'text', 'content': 'See you all at 7 PM.'},
        ],
      },
    ];

    DateTime time = DateTime.now().subtract(const Duration(hours: 1));
    for (var msg in g1Msgs) {
      final mRef = g1Ref.collection('messages').doc();
      batch.set(mRef, {
        'senderId': msg['id'],
        'senderName': msg['name'],
        'senderPhotoUrl': avatars[msg['id']],
        'parts': msg['parts'],
        'timestamp': time,
        'starredBy': [],
      });
      time = time.add(const Duration(minutes: 5));
    }

    // Group 2
    final g2Ref = firestore.collection('groups').doc();
    batch.set(g2Ref, {
      'name': 'Proverbs 31 Women',
      'photoUrl':
          'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=400&q=80', // Nature/grace aesthetic
      'members': [user.uid, 'mock_user_3', 'mock_user_4'],
      'readingProgress': {
        user.uid: 0.0,
        'mock_user_3': 1.0,
        'mock_user_4': 0.5,
      },
      'pinnedScripture': 'Proverbs 31:25',
      'groupType': 'Bible',
      'studyBook': 'Proverbs',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final g2Msgs = [
      {
        'id': 'mock_user_3',
        'name': 'Love',
        'parts': [
          {
            'type': 'text',
            'content': 'Hello everyone! What an amazing service yesterday.',
          },
        ],
      },
      {
        'id': 'mock_user_4',
        'name': 'Dammy',
        'parts': [
          {
            'type': 'text',
            'content': 'I am still meditating on the message. Truly powerful.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {'type': 'text', 'content': 'The worship session was my highlight.'},
        ],
      },
      {
        'id': 'mock_user_3',
        'name': 'Love',
        'parts': [
          {
            'type': 'text',
            'content':
                'I recorded a bit of the worship session, listen to this!',
          },
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 120},
        ],
      },
      {
        'id': 'mock_user_4',
        'name': 'Dammy',
        'parts': [
          {
            'type': 'text',
            'content': 'Oh my, this brings back the atmosphere.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {
            'type': 'text',
            'content': 'Thank you for sharing that Love, so profound!',
          },
        ],
      },
      {
        'id': 'mock_user_3',
        'name': 'Love',
        'parts': [
          {
            'type': 'text',
            'content':
                'You are welcome! Should we start reading Chapter 5 today?',
          },
        ],
      },
      {
        'id': 'mock_user_4',
        'name': 'Dammy',
        'parts': [
          {'type': 'text', 'content': 'Yes, I have already started.'},
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {'type': 'text', 'content': 'I will catch up this evening.'},
        ],
      },
      {
        'id': 'mock_user_4',
        'name': 'Dammy',
        'parts': [
          {'type': 'text', 'content': 'Take your time.'},
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 5},
        ],
      },
    ];

    time = DateTime.now().subtract(const Duration(minutes: 30));
    for (var msg in g2Msgs) {
      final mRef = g2Ref.collection('messages').doc();
      batch.set(mRef, {
        'senderId': msg['id'],
        'senderName': msg['name'],
        'senderPhotoUrl': avatars[msg['id']],
        'parts': msg['parts'],
        'timestamp': time,
        'starredBy': [],
      });
      time = time.add(const Duration(minutes: 3));
    }

    // Group 3 (Topic)
    final g3Ref = firestore.collection('groups').doc();
    batch.set(g3Ref, {
      'name': 'Faith in Action',
      'photoUrl':
          'https://images.unsplash.com/photo-1511895426328-dc8714191300?w=400&q=80', // Community aesthetic
      'members': [user.uid, 'mock_user_1', 'mock_user_4'],
      'readingProgress': {
        user.uid: 0.0,
        'mock_user_1': 0.0,
        'mock_user_4': 0.0,
      },
      'pinnedScripture': '',
      'groupType': 'Topic',
      'topic': 'Grace',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final g3Msgs = [
      {
        'id': 'mock_user_1',
        'name': 'Grace',
        'parts': [
          {
            'type': 'text',
            'content': 'Hi everyone! Excited to discuss Grace this week.',
          },
        ],
      },
      {
        'id': user.uid,
        'name': user.displayName ?? 'Me',
        'parts': [
          {
            'type': 'text',
            'content': 'Same here. I have been reading some materials on it.',
          },
        ],
      },
    ];

    time = DateTime.now().subtract(const Duration(minutes: 10));
    for (var msg in g3Msgs) {
      final mRef = g3Ref.collection('messages').doc();
      batch.set(mRef, {
        'senderId': msg['id'],
        'senderName': msg['name'],
        'senderPhotoUrl': avatars[msg['id']],
        'parts': msg['parts'],
        'timestamp': time,
        'starredBy': [],
      });
      time = time.add(const Duration(minutes: 2));
    }

    // Seed Insights
    final now = DateTime.now();

    final i1Ref = firestore.collection('insights').doc();
    batch.set(i1Ref, {
      'id': i1Ref.id,
      'authorUid': 'mock_user_1',
      'authorName': 'Grace',
      'authorPhotoUrl': avatars['mock_user_1'],
      'title': 'The Law of the Spirit',
      'body':
          'I was studying Romans 8:1-4 today and it hit me how powerful the "law of the Spirit of life" is. It completely overrides the law of sin and death, just like how aerodynamics overrides gravity!',
      'themeId': 'theme_1', // Forest Green
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
      'expiresAt': Timestamp.fromDate(
        now.subtract(const Duration(hours: 2)).add(const Duration(days: 3)),
      ),
    });

    final i2Ref = firestore.collection('insights').doc();
    batch.set(i2Ref, {
      'id': i2Ref.id,
      'authorUid': 'mock_user_2',
      'authorName': 'James',
      'authorPhotoUrl': avatars['mock_user_2'],
      'title': 'Light & Creation',
      'body':
          'Compare Genesis 1:1 with John 1:1-5. The Word was present at the beginning, and the Word brought light into the darkness. Darkness cannot comprehend it.',
      'themeId': 'theme_5', // Ocean Blue
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 5))),
      'expiresAt': Timestamp.fromDate(
        now.subtract(const Duration(hours: 5)).add(const Duration(days: 3)),
      ),
    });

    // Mock comments for Grace's insight
    final c1Ref = i1Ref.collection('comments').doc();
    batch.set(c1Ref, {
      'id': c1Ref.id,
      'insightId': i1Ref.id,
      'authorUid': 'mock_user_2',
      'authorName': 'James',
      'authorPhotoUrl': avatars['mock_user_2'],
      'body': 'This is such a great analogy!',
      'createdAt': Timestamp.fromDate(
        now.subtract(const Duration(minutes: 30)),
      ),
    });

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rich Hybrid Mock groups seeded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}


