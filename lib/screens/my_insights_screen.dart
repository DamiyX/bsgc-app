import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import 'create_insight_screen.dart';
import 'view_insight_screen.dart';
import '../widgets/braid_media.dart';

const myInsightsPrivacyNotice =
    'Visible only to the people you choose while each reflection is active. '
    'Braid stores and processes this content to provide the service.';

ViewInsightScreen buildSelectedInsightViewer(
  List<InsightModel> insights,
  InsightModel selectedInsight, {
  Set<String> seenInsightIds = const {},
}) {
  return ViewInsightScreen(
    userInsightsGroups: [insights],
    initialUserIndex: 0,
    initialInsightId: selectedInsight.id,
    seenInsightIds: seenInsightIds,
  );
}

class MyInsightsScreen extends StatelessWidget {
  MyInsightsScreen({
    super.key,
    MyInsightsDataSource? dataSource,
    String? currentUserId,
    String? currentUserDisplayName,
    String? currentUserPhotoUrl,
  }) : _dataSource = dataSource ?? InsightService(),
       _currentUserId =
           currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '',
       _currentUserDisplayName =
           currentUserDisplayName ??
           (dataSource == null
               ? FirebaseAuth.instance.currentUser?.displayName
               : null) ??
           'You',
       _currentUserPhotoUrl =
           currentUserPhotoUrl ??
           (dataSource == null
               ? FirebaseAuth.instance.currentUser?.photoURL
               : null);

  final MyInsightsDataSource _dataSource;
  final String _currentUserId;
  final String _currentUserDisplayName;
  final String? _currentUserPhotoUrl;

  void _deleteInsight(BuildContext context, InsightModel insight) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete reflection?'),
        content: Text('This will permanently delete this reflection.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _dataSource.deleteInsight(insight.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't delete this reflection. Try again."),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reflection deleted'),
            behavior: SnackBarBehavior.floating,
            elevation: 0,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.87),
        ),
        title: Text(
          'Shared reflections',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.87),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<InsightModel>>(
                stream: _dataSource.getActiveInsightsForUser(_currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: scheme.primary),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Reflections are unavailable'),
                    );
                  }
                  final insights = snapshot.data ?? [];

                  if (insights.isEmpty) {
                    return Center(
                      child: Text(
                        'You have no active reflections.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.54),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    itemCount: insights.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, indent: 76),
                    itemBuilder: (context, index) {
                      final insight = insights[index];
                      return ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      buildSelectedInsightViewer(
                                        insights,
                                        insight,
                                      ),
                              transitionsBuilder:
                                  (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
                                    if (MediaQuery.maybeOf(
                                          context,
                                        )?.disableAnimations ==
                                        true) {
                                      return child;
                                    }
                                    return FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                  },
                            ),
                          );
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(AppSpacing.xxs),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primaryContainer,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.xxs / 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surface,
                            ),
                            child: BraidAvatar(
                              identity: _currentUserId,
                              displayName: _currentUserDisplayName,
                              imageUrl: _currentUserPhotoUrl,
                              radius: 22,
                            ),
                          ),
                        ),
                        title: Text(
                          insight.title.isEmpty
                              ? 'Untitled Note'
                              : insight.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.87),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '${DateFormat('MMM d, HH:mm').format(insight.createdAt)} · Shared with study contacts',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.54),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.54),
                          ),
                          onSelected: (val) {
                            if (val == 'delete') {
                              _deleteInsight(context, insight);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              color: scheme.surfaceContainerLow,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_outlined, size: 14, color: scheme.primary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      myInsightsPrivacyNotice,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.54),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateInsightScreen()),
          );
        },
        foregroundColor: scheme.onPrimary,
        child: const Icon(Icons.edit),
      ),
    );
  }
}
