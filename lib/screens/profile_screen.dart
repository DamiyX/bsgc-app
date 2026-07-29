import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/insight_model.dart';
import '../models/note_model.dart';
import '../services/insight_service.dart';
import '../services/note_service.dart';
import '../widgets/braid_media.dart';
import '../widgets/note_card.dart';
import '../widgets/saved_insight_card.dart';
import 'create_note_screen.dart';
import 'edit_profile_screen.dart';

const savedInsightsRetentionNotice =
    'Saved Insights are bookmarks available while they are active. '
    'Expired or unavailable items are removed.';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final NoteService _noteService = NoteService();
  final InsightService _insightService = InsightService();

  bool _loadingIdentity = true;
  bool _loadingContacts = true;
  bool _hasIdentity = false;
  bool _identityLoadFailed = false;
  bool _contactsLoadFailed = false;
  String _displayName = 'Your space';
  String _bio = 'Growing through Scripture and fellowship.';
  String? _photoUrl;
  int _studyContacts = 0;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadIdentity());
    unawaited(_loadContacts());
  }

  Future<void> _loadIdentity() async {
    if (_uid.isEmpty) return;
    setState(() {
      _loadingIdentity = true;
      _identityLoadFailed = false;
    });
    try {
      final reference = FirebaseFirestore.instance
          .collection('users_public')
          .doc(_uid);
      DocumentSnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await reference.get(
          const GetOptions(source: Source.serverAndCache),
        );
      } on FirebaseException catch (error) {
        if (error.code != 'unavailable' &&
            error.code != 'network-request-failed') {
          rethrow;
        }
        snapshot = await reference.get(const GetOptions(source: Source.cache));
      }
      final profile = snapshot.data();
      if (!mounted) return;
      setState(() {
        _displayName =
            profile?['displayName']?.toString().trim().isNotEmpty == true
            ? profile!['displayName'].toString().trim()
            : 'Your space';
        _bio = profile?['bio']?.toString().trim().isNotEmpty == true
            ? profile!['bio'].toString().trim()
            : 'Growing through Scripture and fellowship.';
        _photoUrl = profile?['photoUrl']?.toString();
        _hasIdentity = snapshot.exists;
        _loadingIdentity = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingIdentity = false;
          _identityLoadFailed = true;
        });
      }
    }
  }

  Future<void> _loadContacts() async {
    if (_uid.isEmpty) return;
    setState(() {
      _loadingContacts = true;
      _contactsLoadFailed = false;
    });
    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('connections')
        .where('status', isEqualTo: 'accepted');
    try {
      int count;
      try {
        count = (await query.count().get()).count ?? 0;
      } on FirebaseException catch (error) {
        if (error.code != 'unavailable' &&
            error.code != 'network-request-failed') {
          rethrow;
        }
        count =
            (await query.limit(500).get(const GetOptions(source: Source.cache)))
                .size;
      }
      if (mounted) {
        setState(() {
          _studyContacts = count;
          _loadingContacts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingContacts = false;
          _contactsLoadFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Profile and saved items')),
        floatingActionButton: FloatingActionButton.extended(
          tooltip: 'Write a private reflection',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateNoteScreen()),
          ),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Write'),
        ),
        body: _uid.isEmpty
            ? const Center(child: Text('Sign in to open your profile.'))
            : Column(
                children: [
                  _buildHeader(),
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.edit_note_rounded), text: 'Notes'),
                      Tab(icon: Icon(Icons.bookmark_outline), text: 'Saved'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [_buildNotes(), _buildSavedInsights()],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_loadingIdentity && !_hasIdentity) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        children: [
          BraidAvatar(
            identity: _uid,
            displayName: _displayName,
            imageUrl: _photoUrl,
            radius: 46,
          ),
          const SizedBox(height: 12),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            _bio,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_identityLoadFailed)
            TextButton.icon(
              onPressed: _loadIdentity,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry profile'),
            ),
          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_contactsLoadFailed)
            TextButton.icon(
              onPressed: _loadContacts,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry study contact count'),
            )
          else
            Text(
              '$_studyContacts accepted study '
              '${_studyContacts == 1 ? 'contact' : 'contacts'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
              if (changed == true) await _loadIdentity();
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotes() {
    return StreamBuilder<List<NoteModel>>(
      stream: _noteService.getUserNotes(_uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return const _ProfileListState(
            icon: Icons.cloud_off_outlined,
            title: 'Notes are not available yet',
          );
        }
        final notes = snapshot.data ?? const <NoteModel>[];
        if (notes.isEmpty) {
          return const _ProfileListState(
            icon: Icons.edit_note_rounded,
            title: 'No private reflections yet',
            description: 'Your Journal is visible only to you.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: notes.length,
          itemBuilder: (context, index) => NoteCard(
            note: notes[index],
            onDelete: () => unawaited(_deleteNote(notes[index])),
          ),
        );
      },
    );
  }

  Widget _buildSavedInsights() {
    return StreamBuilder<List<InsightModel>>(
      stream: _insightService.getSavedInsights(_uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return const _ProfileListState(
            icon: Icons.cloud_off_outlined,
            title: 'Saved Insights are not available yet',
          );
        }
        final insights = snapshot.data ?? const <InsightModel>[];
        if (insights.isEmpty) {
          return const _ProfileListState(
            icon: Icons.bookmark_outline,
            title: 'Nothing saved yet',
            description: savedInsightsRetentionNotice,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: insights.length,
          itemBuilder: (context, index) => SavedInsightCard(
            insight: insights[index],
            onDelete: () => unawaited(
              _insightService.unsaveInsight(_uid, insights[index].id),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteNote(NoteModel note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this private reflection?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _noteService.deleteNote(_uid, note.id);
    }
  }
}

class _ProfileListState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;

  const _ProfileListState({
    required this.icon,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(description!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
