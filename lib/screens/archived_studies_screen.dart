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
  late Future<List<GroupModel>> _studiesFuture;

  @override
  void initState() {
    super.initState();
    _studiesFuture = _chatService.getArchivedGroups();
  }

  void _retry() {
    setState(() => _studiesFuture = _chatService.getArchivedGroups());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived studies')),
      body: FutureBuilder<List<GroupModel>>(
        future: _studiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ArchiveState(
              icon: Icons.cloud_off_outlined,
              title: 'Archived studies are unavailable',
              message: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: _retry,
                child: const Text('Try again'),
              ),
            );
          }

          final studies = snapshot.data ?? const <GroupModel>[];
          if (studies.isEmpty) {
            return const _ArchiveState(
              icon: Icons.archive_outlined,
              title: 'No archived studies yet',
              message:
                  'Completed or archived studies will stay here as read-only records.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              itemCount: studies.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final study = studies[index];
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
