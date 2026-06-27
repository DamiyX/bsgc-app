import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../models/group_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'study_room_screen.dart';
import 'create_group_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets/insights_row.dart';

class MainHallScreen extends StatelessWidget {
  const MainHallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final chatService = ChatService();

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Your Groups',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black54),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search coming soon!')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.data_usage, color: Colors.black54),
            tooltip: 'Seed Mock Data',
            onPressed: () async {
              await _seedMockData(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InsightsRow(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Text(
                  'Your Groups',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<GroupModel>>(
                  stream: chatService.getUserGroups(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.black));
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error loading groups'));
                    }
                    final groups = snapshot.data ?? [];
                    if (groups.isEmpty) {
                      return const Center(
                        child: Text(
                          'You are not in any groups yet.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.black12, height: 1),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudyRoomScreen(group: group),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 64,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                    image: group.photoUrl != null && group.photoUrl!.isNotEmpty
                                        ? DecorationImage(image: NetworkImage(group.photoUrl!), fit: BoxFit.cover)
                                        : null,
                                  ),
                                  child: group.photoUrl == null || group.photoUrl!.isEmpty
                                      ? const Icon(Icons.book, size: 28, color: Colors.black45)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                const Padding(
                                  padding: EdgeInsets.only(top: 8.0),
                                  child: Icon(Icons.chevron_right, color: Colors.black26),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fade(duration: 300.ms, delay: (index * 50).ms).slideY(begin: 0.1, duration: 300.ms, curve: Curves.easeOutQuad);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CreateGroupScreen(chatService: chatService)),
          );
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildGroupSubtitle(GroupModel group) {
    if (group.startDate == null || group.endDate == null) {
      if (group.groupType == 'Bible') {
        return Text('Book: ${group.studyBook ?? 'None'}', style: const TextStyle(color: Colors.black54));
      } else {
        return Text('Topic: ${group.topic ?? 'None'}', style: const TextStyle(color: Colors.black54));
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
      style: const TextStyle(
        fontSize: 13,
        color: Colors.black54,
      ),
    );
  }

  Future<void> _seedMockData(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    
    // Tiny valid base64 wav header so it doesn't crash AudioPlayer
    const dummyAudio = 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';

    final avatars = {
      'mock_user_1': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150&q=80', // Woman profile
      'mock_user_2': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=150&q=80', // Man profile
      'mock_user_3': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&q=80', // Woman profile
      'mock_user_4': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&q=80', // Woman profile
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
      'photoUrl': 'https://images.unsplash.com/photo-1544411047-c45ba52fb7a0?w=400&q=80', // Bible/reading aesthetic
      'members': [user.uid, 'mock_user_1', 'mock_user_2'],
      'readingProgress': { user.uid: 0.0, 'mock_user_1': 0.3, 'mock_user_2': 0.8 },
      'pinnedScripture': 'Proverbs 27:17',
      'groupType': 'Bible',
      'studyBook': 'Proverbs',
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    final g1Msgs = [
      {
        'id': 'mock_user_1', 'name': 'Jack',
        'parts': [{'type': 'text', 'content': 'Welcome to the Monday Fellowship!'}]
      },
      {
        'id': 'mock_user_2', 'name': 'James',
        'parts': [{'type': 'text', 'content': 'Looking forward to our study tonight. Who is leading the prayer?'}]
      },
      {
        'id': 'mock_user_1', 'name': 'Jack',
        'parts': [{'type': 'text', 'content': 'I will be leading the opening prayer today.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'Great! I have some questions on the previous chapter.'}]
      },
      {
        'id': 'mock_user_1', 'name': 'Jack',
        'parts': [
          {'type': 'text', 'content': 'Sure, drop them here.'},
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 15},
        ]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'I was wondering about the context of verse 10.'}]
      },
      {
        'id': 'mock_user_2', 'name': 'James',
        'parts': [
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 42},
          {'type': 'text', 'content': 'I tried to explain it in this voice note.'},
        ]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'Wow, that makes so much sense now. Thank you, James!'}]
      },
      {
        'id': 'mock_user_1', 'name': 'Jack',
        'parts': [{'type': 'text', 'content': 'Exactly! James nailed it.'}]
      },
      {
        'id': 'mock_user_2', 'name': 'James',
        'parts': [{'type': 'text', 'content': 'Glory to God.'}]
      },
      {
        'id': 'mock_user_1', 'name': 'Jack',
        'parts': [{'type': 'text', 'content': 'Let us prepare for the evening session now.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'See you all at 7 PM.'}]
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
      'photoUrl': 'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=400&q=80', // Nature/grace aesthetic
      'members': [user.uid, 'mock_user_3', 'mock_user_4'],
      'readingProgress': { user.uid: 0.0, 'mock_user_3': 1.0, 'mock_user_4': 0.5 },
      'pinnedScripture': 'Proverbs 31:25',
      'groupType': 'Bible',
      'studyBook': 'Proverbs',
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    final g2Msgs = [
      {
        'id': 'mock_user_3', 'name': 'Love',
        'parts': [{'type': 'text', 'content': 'Hello everyone! What an amazing service yesterday.'}]
      },
      {
        'id': 'mock_user_4', 'name': 'Dammy',
        'parts': [{'type': 'text', 'content': 'I am still meditating on the message. Truly powerful.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'The worship session was my highlight.'}]
      },
      {
        'id': 'mock_user_3', 'name': 'Love',
        'parts': [
          {'type': 'text', 'content': 'I recorded a bit of the worship session, listen to this!'},
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 120},
        ]
      },
      {
        'id': 'mock_user_4', 'name': 'Dammy',
        'parts': [{'type': 'text', 'content': 'Oh my, this brings back the atmosphere.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'Thank you for sharing that Love, so profound!'}]
      },
      {
        'id': 'mock_user_3', 'name': 'Love',
        'parts': [{'type': 'text', 'content': 'You are welcome! Should we start reading Chapter 5 today?'}]
      },
      {
        'id': 'mock_user_4', 'name': 'Dammy',
        'parts': [{'type': 'text', 'content': 'Yes, I have already started.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'I will catch up this evening.'}]
      },
      {
        'id': 'mock_user_4', 'name': 'Dammy',
        'parts': [
          {'type': 'text', 'content': 'Take your time.'},
          {'type': 'voice', 'content': dummyAudio, 'durationSeconds': 5},
        ]
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
      'photoUrl': 'https://images.unsplash.com/photo-1511895426328-dc8714191300?w=400&q=80', // Community aesthetic
      'members': [user.uid, 'mock_user_1', 'mock_user_4'],
      'readingProgress': { user.uid: 0.0, 'mock_user_1': 0.0, 'mock_user_4': 0.0 },
      'pinnedScripture': '',
      'groupType': 'Topic',
      'topic': 'Grace',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final g3Msgs = [
      {
        'id': 'mock_user_1', 'name': 'Grace',
        'parts': [{'type': 'text', 'content': 'Hi everyone! Excited to discuss Grace this week.'}]
      },
      {
        'id': user.uid, 'name': user.displayName ?? 'Me',
        'parts': [{'type': 'text', 'content': 'Same here. I have been reading some materials on it.'}]
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
      'body': 'I was studying Romans 8:1-4 today and it hit me how powerful the "law of the Spirit of life" is. It completely overrides the law of sin and death, just like how aerodynamics overrides gravity!',
      'themeColor': 0xFF1B5E20, // Forest Green
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
      'expiresAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2)).add(const Duration(days: 3))),
    });

    final i2Ref = firestore.collection('insights').doc();
    batch.set(i2Ref, {
      'id': i2Ref.id,
      'authorUid': 'mock_user_2',
      'authorName': 'James',
      'authorPhotoUrl': avatars['mock_user_2'],
      'title': 'Light & Creation',
      'body': 'Compare Genesis 1:1 with John 1:1-5. The Word was present at the beginning, and the Word brought light into the darkness. Darkness cannot comprehend it.',
      'themeColor': 0xFF01579B, // Ocean Blue
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 5))),
      'expiresAt': Timestamp.fromDate(now.subtract(const Duration(hours: 5)).add(const Duration(days: 3))),
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
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 30))),
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
