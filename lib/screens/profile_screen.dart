import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'edit_profile_screen.dart';
import 'create_note_screen.dart';
import '../models/insight_model.dart';
import '../models/note_model.dart';
import '../services/insight_service.dart';
import '../services/note_service.dart';
import '../widgets/note_card.dart';
import '../widgets/saved_insight_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = false;
  late Stream<List<NoteModel>> _notesStream;
  late Stream<List<InsightModel>> _savedInsightsStream;
  int _directReach = 0;
  int _extendedReach = 0;
  int _insightsCount = 0;
  
  int _notesCount = 0;
  int _savesCount = 0;
  
  String _displayName = '';
  String _bio = '';
  String _searchQuery = '';
  String _filterMode = 'Recent'; // 'Recent' or 'Oldest'
  bool _showNetworkBreakdown = false; // Toggle for network stats

  String _photoUrl = '';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _notesStream = NoteService().getUserNotes(user.uid);
      _savedInsightsStream = InsightService().getSavedInsights(user.uid);
    }
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      
      // Fetch User Document for details
      final userDoc = await db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _displayName = data['displayName'] ?? 'Believer';
        _bio = data['bio'] ?? 'Growing in grace and knowledge.';
        _photoUrl = data['photoURL'] ?? '';
      }
      
      // Get Gen 1 (Direct Reach)
      final gen1Snapshot = await db.collection('users').where('referredBy', isEqualTo: user.uid).get();
      final List<String> gen1Ids = gen1Snapshot.docs.map((d) => d.id).toList();
      
      int gen2Total = 0;
      
      // Get Gen 2 (Extended Reach)
      if (gen1Ids.isNotEmpty) {
        for (String id in gen1Ids) {
          final gen2Snapshot = await db.collection('users').where('referredBy', isEqualTo: id).get();
          gen2Total += gen2Snapshot.docs.length;
        }
      }

      // Get Insights Count
      final insightsSnapshot = await db.collection('insights').where('authorUid', isEqualTo: user.uid).get();

      // Get Notes and Saves Count for Tabs
      final notesSnapshot = await db.collection('users').doc(user.uid).collection('notes').get();
      final savesSnapshot = await db.collection('users').doc(user.uid).collection('saved_insights').get();

      if (mounted) {
        setState(() {
          _directReach = gen1Ids.length;
          _extendedReach = gen2Total;
          _insightsCount = insightsSnapshot.docs.length;
          _notesCount = notesSnapshot.docs.length;
          _savesCount = savesSnapshot.docs.length;
        });
      }
    } catch (e) {
      debugPrint('Error calculating profile stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(_displayName.isNotEmpty ? _displayName : 'Profile', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Comfortaa')),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.gradientEnd,
          child: const Icon(Icons.add, color: Colors.white),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateNoteScreen())).then((_) => _fetchProfileData());
          },
        ),
        body: RefreshIndicator(
                onRefresh: _fetchProfileData,
                color: AppColors.gradientStart,
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Section: DP & Stats
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                children: [
                                  // Left: Display Picture
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade300, width: 1),
                                    ),
                                    child: CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
                                      child: _photoUrl.isEmpty 
                                          ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  
                                  // Right: Stats Row
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Insights real-time stat
                                            _buildStatColumn('Insights', _insightsCount),
                                            // Network expandable stat
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _showNetworkBreakdown = !_showNetworkBreakdown;
                                                });
                                              },
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        (_directReach + _extendedReach).toString(),
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                                      ),
                                                      Icon(
                                                        _showNetworkBreakdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                                        size: 18,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  const Text(
                                                    'Network',
                                                    style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Network Breakdown Dropdown
                                        if (_showNetworkBreakdown)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 12.0),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.grey.shade200),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                children: [
                                                  _buildStatColumn('Direct', _directReach),
                                                  _buildStatColumn('Indirect', _extendedReach),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Bio Section
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _bio,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Action Buttons Row
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.black,
                                        side: BorderSide(color: Colors.grey.shade300),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      onPressed: () async {
                                        final updated = await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                                        );
                                        if (updated == true) {
                                          setState(() => _isLoading = true);
                                          _fetchProfileData();
                                        }
                                      },
                                      child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.black,
                                        side: BorderSide(color: Colors.grey.shade300),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      onPressed: () {
                                        final user = FirebaseAuth.instance.currentUser;
                                        if (user != null) {
                                          final inviteLink = 'https://bsgc-app.web.app/invite?inviter=${user.uid}';
                                          Share.share(
                                            'Join me on Braid, a community of believers growing together in faith!\n\n$inviteLink',
                                          );
                                        }
                                      },
                                      child: const Text('Share Braid', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverAppBarDelegate(
                          TabBar(
                            labelColor: AppColors.gradientEnd,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: AppColors.gradientEnd,
                            indicatorWeight: 3,
                            tabs: [
                              Tab(
                                child: StreamBuilder<List<NoteModel>>(
                                  stream: NoteService().getUserNotes(FirebaseAuth.instance.currentUser?.uid ?? ''),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      _notesCount = snapshot.data!.length;
                                    }
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.description_outlined, size: 20),
                                        const SizedBox(width: 8),
                                        Text('Note $_notesCount', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    );
                                  }
                                ),
                              ),
                              Tab(
                                child: StreamBuilder<List<InsightModel>>(
                                  stream: InsightService().getSavedInsights(FirebaseAuth.instance.currentUser?.uid ?? ''),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      _savesCount = snapshot.data!.length;
                                    }
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.bookmark_border, size: 20),
                                        const SizedBox(width: 8),
                                        Text('Saved $_savesCount', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    );
                                  }
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Search and Filter Bar Sticky
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverSearchDelegate(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search...',
                                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _searchQuery = val.toLowerCase();
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _filterMode,
                                      icon: const Icon(Icons.filter_list, size: 18),
                                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                                      items: ['Recent', 'Oldest'].map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _filterMode = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    children: [
                      _buildNotesView(),
                      _buildSavedMessagesView(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatColumn(String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildNotesView() {
    return StreamBuilder<List<NoteModel>>(
      stream: _notesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.gradientEnd));
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Failed to load notes.'));
        }
        var notes = snapshot.data ?? [];
        
        // Apply Filter
        if (_filterMode == 'Oldest') {
          notes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        
        // Apply Search
        if (_searchQuery.isNotEmpty) {
          notes = notes.where((n) => 
            n.body.toLowerCase().contains(_searchQuery)
          ).toList();
        }

        if (notes.isEmpty) {
          return const Center(child: Text('No notes found.', style: TextStyle(color: Colors.grey)));
        }
        
        return GridView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return NoteCard(
              note: note,
              isGrid: true,
              onDelete: () {
                NoteService().deleteNote(FirebaseAuth.instance.currentUser!.uid, note.id);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note deleted')));
                _fetchProfileData(); // update count
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSavedMessagesView() {
    return StreamBuilder<List<InsightModel>>(
      stream: _savedInsightsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.gradientEnd));
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Failed to load saved messages.'));
        }
        var saved = snapshot.data ?? [];
        
        // Apply Filter
        if (_filterMode == 'Oldest') {
          saved.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          saved.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        
        // Apply Search
        if (_searchQuery.isNotEmpty) {
          saved = saved.where((s) => 
            s.body.toLowerCase().contains(_searchQuery) ||
            s.authorName.toLowerCase().contains(_searchQuery)
          ).toList();
        }

        if (saved.isEmpty) {
          return const Center(child: Text('No saved messages.', style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
          itemCount: saved.length,
          itemBuilder: (context, index) {
            final note = saved[index];
            return SavedInsightCard(
              insight: note,
              onDelete: () {
                InsightService().unsaveInsight(FirebaseAuth.instance.currentUser?.uid ?? '', note.id);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unsaved note')));
                _fetchProfileData(); // update count
              },
            );
          },
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _SliverSearchDelegate extends SliverPersistentHeaderDelegate {
  _SliverSearchDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 60.0;
  @override
  double get maxExtent => 60.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverSearchDelegate oldDelegate) {
    return true; // Rebuild when search state changes
  }
}
