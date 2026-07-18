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
  int _interactionCount = 0;
  
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

      // Get Notes and Saves Count for Tabs
      final notesSnapshot = await db.collection('users').doc(user.uid).collection('notes').get();
      final savesSnapshot = await db.collection('users').doc(user.uid).collection('saved_insights').get();

      final currentMonth = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}";
      int currentInteractionCount = 0;
      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['interactionMonth'] == currentMonth) {
           currentInteractionCount = data['interactionCount'] ?? 0;
        }
      }

      if (mounted) {
        setState(() {
          _directReach = gen1Ids.length;
          _extendedReach = gen2Total;
          _interactionCount = currentInteractionCount;
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_displayName.isNotEmpty ? _displayName : 'Profile', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Comfortaa')),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.gradientEnd,
          child: Icon(Icons.add, color: Colors.white),
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
                              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                children: [
                                  // Left: Display Picture
                                  GestureDetector(
                                    onTap: () {
                                      if (_photoUrl.isNotEmpty) {
                                        showDialog(
                                          context: context,
                                          builder: (_) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            insetPadding: EdgeInsets.all(0),
                                            child: GestureDetector(
                                              onTap: () => Navigator.pop(context),
                                              child: InteractiveViewer(
                                                child: Image.network(_photoUrl, fit: BoxFit.contain),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: [AppColors.gradientStart, AppColors.gradientEnd],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: Container(
                                        padding: EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                        ),
                                        child: CircleAvatar(
                                          radius: 40,
                                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          backgroundImage: _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
                                          child: _photoUrl.isEmpty 
                                              ? Icon(Icons.person, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant)
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 24),
                                  
                                  // Right: Stats Row
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Insights stat
                                            _buildStatColumn('Insights', _notesCount),
                                            // Interactions real-time stat
                                            GestureDetector(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: Text('Interactions'),
                                                    content: Text('This measures your engagement and activity within your study groups for the current month. Keep participating to grow your score!'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context),
                                                        child: Text('Got it', style: TextStyle(color: AppColors.gradientEnd)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                              child: _buildStatColumn('Interactions', _interactionCount),
                                            ),
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
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                                      ),
                                                      Icon(
                                                        _showNetworkBreakdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                                        size: 18,
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 2),
                                                  Text(
                                                    'Network',
                                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Network Breakdown Dropdown
                                        if (_showNetworkBreakdown)
                                          Padding(
                                            padding: EdgeInsets.only(top: 12.0),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.surface,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
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
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayName,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    _bio,
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            
                            SizedBox(height: 16),
                            
                            // Action Buttons Row
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                                        side: BorderSide(color: Theme.of(context).dividerColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: EdgeInsets.symmetric(vertical: 8),
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
                                      child: Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                                        side: BorderSide(color: Theme.of(context).dividerColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: EdgeInsets.symmetric(vertical: 8),
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
                                      child: Text('Share Braid', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 16),
                          ],
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverAppBarDelegate(
                          TabBar(
                            labelColor: AppColors.gradientEnd,
                            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                        Icon(Icons.description_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text('Note $_notesCount', style: TextStyle(fontWeight: FontWeight.w600)),
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
                                        Icon(Icons.bookmark_border, size: 20),
                                        SizedBox(width: 8),
                                        Text('Saved $_savesCount', style: TextStyle(fontWeight: FontWeight.w600)),
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
                            color: Theme.of(context).scaffoldBackgroundColor,
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search...',
                                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surfaceContainer,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _searchQuery = val.toLowerCase();
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: 12),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _filterMode,
                                      icon: Icon(Icons.filter_list, size: 18),
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.w600),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildNotesView() {
    return StreamBuilder<List<NoteModel>>(
      stream: _notesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load notes.'));
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
          return Center(child: Text('No notes found.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
        }
        
        return GridView.builder(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
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
              onDelete: () async {
                await NoteService().deleteNote(FirebaseAuth.instance.currentUser!.uid, note.id);
                _fetchProfileData(); // update count
                if (mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Note deleted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      behavior: SnackBarBehavior.floating,
                      elevation: 0,
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      action: SnackBarAction(
                        label: 'UNDO',
                        textColor: AppColors.gradientStart,
                        onPressed: () async {
                          await NoteService().saveNote(note);
                          _fetchProfileData();
                        },
                      ),
                    ),
                  );
                }
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
          return SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load saved messages.'));
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
          return Center(child: Text('No saved messages.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
        }
        return ListView.builder(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
          itemCount: saved.length,
          itemBuilder: (context, index) {
            final note = saved[index];
            return SavedInsightCard(
              insight: note,
              onDelete: () async {
                await InsightService().unsaveInsight(FirebaseAuth.instance.currentUser?.uid ?? '', note.id);
                _fetchProfileData(); // update count
                if (mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Insight unsaved', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      behavior: SnackBarBehavior.floating,
                      elevation: 0,
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      action: SnackBarAction(
                        label: 'UNDO',
                        textColor: AppColors.gradientStart,
                        onPressed: () async {
                          await InsightService().saveInsight(FirebaseAuth.instance.currentUser?.uid ?? '', note);
                          _fetchProfileData();
                        },
                      ),
                    ),
                  );
                }
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
      color: Theme.of(context).scaffoldBackgroundColor,
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
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverSearchDelegate oldDelegate) {
    return true; // Rebuild when search state changes
  }
}
