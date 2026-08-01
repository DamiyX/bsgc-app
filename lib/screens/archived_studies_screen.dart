import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group_model.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/braid_media.dart';
import 'study_room_screen.dart';

class ArchivedStudiesScreen extends StatefulWidget {
  const ArchivedStudiesScreen({super.key});

  @override
  State<ArchivedStudiesScreen> createState() => _ArchivedStudiesScreenState();
}

class _ArchivedStudiesScreenState extends State<ArchivedStudiesScreen> {
  final ChatService _chatService = ChatService();
  List<GroupModel> _studies = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstPage());
  }

  Future<void> _loadFirstPage() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _error = StateError('Sign in to view archived studies.');
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _studies = const [];
      _cursor = null;
      _hasMore = false;
    });
    try {
      final page = await _chatService.getArchivedGroupPage(userId: userId);
      if (!mounted) return;
      setState(() {
        _studies = page.groups;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw StateError('Sign in to view archived studies.');
      final page = await _chatService.getArchivedGroupPage(
        userId: userId,
        after: _cursor,
      );
      if (!mounted) return;
      final byId = <String, GroupModel>{
        for (final group in _studies) group.id: group,
        for (final group in page.groups) group.id: group,
      };
      setState(() {
        _studies = ChatService.sortArchivedGroups(byId.values);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _error = null;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived studies')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _studies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _studies.isEmpty) {
      return _ArchiveState(
        icon: Icons.cloud_off_outlined,
        title: 'Archived studies are unavailable',
        message: 'Check your connection and try again.',
        action: FilledButton(
          onPressed: _loadFirstPage,
          child: const Text('Try again'),
        ),
      );
    }

    if (_studies.isEmpty) {
      return const _ArchiveState(
        icon: Icons.archive_outlined,
        title: 'No archived studies yet',
        message:
            'Completed or archived studies will stay here as read-only records.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        itemCount: _studies.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, index) => index == _studies.length - 1
            ? const SizedBox(height: AppSpacing.xs)
            : const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == _studies.length) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history_rounded),
                label: Text(
                  _loadingMore
                      ? 'Loading older studies…'
                      : _error == null
                      ? 'Load older studies'
                      : 'Retry older studies',
                ),
              ),
            );
          }
          final study = _studies[index];
          return Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 82,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              leading: BraidCoverImage(
                identity: study.id,
                imageUrl: study.photoUrl,
                width: 58,
                height: 64,
                borderRadius: AppRadii.small,
                semanticLabel: '${study.name} study cover',
              ),
              title: Text(
                study.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Archived • read-only'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudyRoomScreen(group: study),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArchiveState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _ArchiveState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
