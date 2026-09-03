import 'dart:async';

import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../services/deletion_semantics.dart';
import '../services/insight_service.dart';
import 'create_insight_screen.dart';
import 'view_insight_screen.dart';
import '../widgets/current_user_avatar.dart';

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

typedef SelectedInsightViewerBuilder = Widget Function(
  List<InsightModel> insights,
  InsightModel selectedInsight, {
  Set<String> seenInsightIds,
});

class MyInsightsScreen extends StatefulWidget {
  MyInsightsScreen({
    super.key,
    MyInsightsDataSource? dataSource,
    String? currentUserId,
    String? currentUserDisplayName,
    String? currentUserPhotoUrl,
    this.viewerBuilder,
  })  : dataSource = dataSource ?? InsightService(),
        currentUserId =
            currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '',
        currentUserDisplayName = currentUserDisplayName ??
            (dataSource == null
                ? FirebaseAuth.instance.currentUser?.displayName
                : null) ??
            'You',
        currentUserPhotoUrl = currentUserPhotoUrl ??
            (dataSource == null
                ? FirebaseAuth.instance.currentUser?.photoURL
                : null),
        useCanonicalProfile = dataSource == null;

  final MyInsightsDataSource dataSource;
  final String currentUserId;
  final String currentUserDisplayName;
  final String? currentUserPhotoUrl;
  final bool useCanonicalProfile;
  final SelectedInsightViewerBuilder? viewerBuilder;

  @override
  State<MyInsightsScreen> createState() => _MyInsightsScreenState();
}

class _MyInsightsScreenState extends State<MyInsightsScreen> {
  StreamSubscription<List<InsightModel>>? _insightsSubscription;
  StreamSubscription<Set<String>>? _seenSubscription;
  List<InsightModel>? _insights;
  Set<String> _seenInsightIds = const {};
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(MyInsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource ||
        oldWidget.currentUserId != widget.currentUserId) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    _isLoading = true;
    _error = null;
    _insightsSubscription =
        widget.dataSource.getActiveInsightsForUser(widget.currentUserId).listen(
      (data) {
        if (mounted) {
          setState(() {
            _insights = data;
            _isLoading = false;
            _error = null;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error;
            _isLoading = false;
          });
        }
      },
    );
    _seenSubscription = widget.dataSource.getSeenInsightIds().listen(
      (seen) {
        if (mounted) {
          setState(() {
            _seenInsightIds = seen;
          });
        }
      },
      onError: (_) {
        // Keep default empty set if read status fails
      },
    );
  }

  void _unsubscribe() {
    _insightsSubscription?.cancel();
    _insightsSubscription = null;
    _seenSubscription?.cancel();
    _seenSubscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _deleteInsight(BuildContext context, InsightModel insight) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(insightDeletionDialogTitle),
        content: const Text(insightDeletionDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              insightDeletionActionLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.dataSource.deleteInsight(insight.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't remove this reflection. Try again."),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(insightDeletionSuccessMessage),
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
              child: Builder(
                builder: (context) {
                  if (_isLoading) {
                    return Center(
                      child: CircularProgressIndicator(color: scheme.primary),
                    );
                  }
                  if (_error != null) {
                    return const Center(
                      child: Text('Reflections are unavailable'),
                    );
                  }
                  final insights = _insights ?? [];

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
                      final isUnseen = !_seenInsightIds.contains(insight.id);
                      return ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        onTap: () {
                          final builder = widget.viewerBuilder ??
                              buildSelectedInsightViewer;
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      builder(
                                insights,
                                insight,
                                seenInsightIds: _seenInsightIds,
                              ),
                              transitionsBuilder: (
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
                            child: CurrentUserAvatar(
                              userId: widget.currentUserId,
                              fallbackDisplayName:
                                  widget.currentUserDisplayName,
                              fallbackPhotoUrl: widget.currentUserPhotoUrl,
                              radius: 22,
                              useCanonicalProfile: widget.useCanonicalProfile,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                insight.title.isEmpty
                                    ? 'Untitled Note'
                                    : insight.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Theme.of(
                                    context,
                                  )
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.87),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isUnseen)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.primary,
                                ),
                              ),
                          ],
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
                          onSelected: (value) {
                            if (value == 'delete') {
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
