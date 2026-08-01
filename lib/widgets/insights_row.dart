import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../screens/create_insight_screen.dart';
import '../screens/view_insight_screen.dart';
import '../services/contact_cache_service.dart';
import '../theme.dart';
import 'braid_media.dart';
import 'current_user_avatar.dart';

class InsightsRow extends StatefulWidget {
  final bool embedded;

  const InsightsRow({super.key, this.embedded = false});

  @override
  State<InsightsRow> createState() => _InsightsRowState();
}

class _InsightsRowState extends State<InsightsRow> {
  final InsightService _insightService = InsightService();
  late Stream<List<InsightModel>> _insightsStream;
  late Stream<Set<String>> _seenInsightIdsStream;

  @override
  void initState() {
    super.initState();
    _insightsStream = _insightService.getActiveInsights();
    _seenInsightIdsStream = _insightService.getSeenInsightIds();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Text(
              'Reflections',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.87),
              ),
            ),
          ),
        SizedBox(
          height: 154,
          child: StreamBuilder<List<InsightModel>>(
            stream: _insightsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Reflections are unavailable'));
              }

              final insights = snapshot.data ?? [];

              final Map<String, List<InsightModel>> groupedInsights = {};
              for (var insight in insights) {
                if (!groupedInsights.containsKey(insight.authorUid)) {
                  groupedInsights[insight.authorUid] = [];
                }
                groupedInsights[insight.authorUid]!.add(insight);
              }

              final currentUserId = FirebaseAuth.instance.currentUser?.uid;
              bool hasMyInsights =
                  currentUserId != null &&
                  groupedInsights.containsKey(currentUserId);
              List<InsightModel>? myInsights = hasMyInsights
                  ? groupedInsights[currentUserId]
                  : null;

              final sortedUserIds = groupedInsights.keys
                  .where((id) => id != currentUserId)
                  .toList();
              sortedUserIds.sort((a, b) {
                final latestA = groupedInsights[a]!
                    .map((i) => i.updatedAt)
                    .reduce((x, y) => x.isAfter(y) ? x : y);
                final latestB = groupedInsights[b]!
                    .map((i) => i.updatedAt)
                    .reduce((x, y) => x.isAfter(y) ? x : y);
                return latestB.compareTo(latestA);
              });

              List<List<InsightModel>> globalGroupedList = [];
              if (hasMyInsights) {
                globalGroupedList.add(
                  myInsights!
                    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)),
                );
              }
              for (var uId in sortedUserIds) {
                globalGroupedList.add(
                  groupedInsights[uId]!
                    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)),
                );
              }

              return StreamBuilder<Set<String>>(
                stream: _seenInsightIdsStream,
                initialData: const {},
                builder: (context, seenSnapshot) {
                  if (seenSnapshot.hasError) {
                    return const Center(
                      child: Text("Couldn't load reflection read status"),
                    );
                  }
                  final seenInsightIds = seenSnapshot.data ?? const <String>{};
                  return ListView.builder(
                    padding: EdgeInsets.only(left: 24, right: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: sortedUserIds.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildMyInsightBox(
                          context,
                          hasMyInsights,
                          globalGroupedList,
                          seenInsightIds,
                        );
                      }

                      final userId = sortedUserIds[index - 1];
                      final userInsights = groupedInsights[userId]!;
                      final userIndex = hasMyInsights ? index : index - 1;
                      return _buildUserInsightBubble(
                        context,
                        userInsights,
                        globalGroupedList,
                        userIndex,
                        seenInsightIds,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMyInsightBox(
    BuildContext context,
    bool hasMyInsights,
    List<List<InsightModel>> globalGroupedList,
    Set<String> seenInsightIds,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    final reflections = hasMyInsights ? globalGroupedList.first : const [];
    final unreadCount = reflections
        .where((insight) => !seenInsightIds.contains(insight.id))
        .length;

    return _ReflectionCard(
      title: hasMyInsights ? 'Your reflections' : 'Start a reflection',
      subtitle: hasMyInsights
          ? '${reflections.length} active reflection${reflections.length == 1 ? '' : 's'}${unreadCount == 0 ? '' : ' • $unreadCount to read'}'
          : 'Keep a thought private, or choose people to share it with.',
      avatar: CurrentUserAvatar(
        userId: user?.uid ?? '',
        fallbackDisplayName: user?.displayName ?? 'You',
        fallbackPhotoUrl: user?.photoURL,
        radius: 24,
      ),
      icon: hasMyInsights
          ? Icons.auto_stories_outlined
          : Icons.add_circle_outline_rounded,
      onTap: () {
        if (hasMyInsights) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ViewInsightScreen(
                userInsightsGroups: globalGroupedList,
                initialUserIndex: 0,
                seenInsightIds: seenInsightIds,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateInsightScreen()),
          );
        }
      },
    );
  }

  Widget _buildUserInsightBubble(
    BuildContext context,
    List<InsightModel> userInsights,
    List<List<InsightModel>> globalGroupedList,
    int userIndex,
    Set<String> seenInsightIds,
  ) {
    final authorName = ContactCacheService().getContactName(
      userInsights.first.authorUid,
      userInsights.first.authorName,
    );
    final authorPhotoUrl = userInsights.first.authorPhotoUrl;

    final unreadCount = userInsights
        .where((insight) => !seenInsightIds.contains(insight.id))
        .length;

    return _ReflectionCard(
      title: authorName.split(' ').first,
      subtitle:
          '${userInsights.length} reflection${userInsights.length == 1 ? '' : 's'}${unreadCount == 0 ? '' : ' • $unreadCount to read'}',
      avatar: BraidAvatar(
        identity: userInsights.first.authorUid,
        displayName: authorName,
        imageUrl: authorPhotoUrl,
        radius: 24,
      ),
      icon: Icons.arrow_forward_rounded,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewInsightScreen(
              userInsightsGroups: globalGroupedList,
              initialUserIndex: userIndex,
              seenInsightIds: seenInsightIds,
            ),
          ),
        );
      },
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget avatar;
  final IconData icon;
  final VoidCallback onTap;

  const _ReflectionCard({
    required this.title,
    required this.subtitle,
    required this.avatar,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 216,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    avatar,
                    const Spacer(),
                    Icon(icon, size: 20, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
