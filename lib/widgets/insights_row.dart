import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../screens/create_insight_screen.dart';
import '../screens/view_insight_screen.dart';
import '../screens/my_insights_screen.dart';
import '../services/contact_cache_service.dart';
import '../theme.dart';

class InsightsRow extends StatefulWidget {
  const InsightsRow({super.key});

  @override
  State<InsightsRow> createState() => _InsightsRowState();
}

class _InsightsRowState extends State<InsightsRow> {
  final InsightService _insightService = InsightService();
  late Stream<List<InsightModel>> _insightsStream;

  @override
  void initState() {
    super.initState();
    _insightsStream = _insightService.getActiveInsights();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Text(
            'Insights',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: StreamBuilder<List<InsightModel>>(
            stream: _insightsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error loading insights'));
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
              bool hasMyInsights = currentUserId != null && groupedInsights.containsKey(currentUserId);
              List<InsightModel>? myInsights = hasMyInsights ? groupedInsights[currentUserId] : null;
              
              final sortedUserIds = groupedInsights.keys.where((id) => id != currentUserId).toList();
              sortedUserIds.sort((a, b) {
                final latestA = groupedInsights[a]!.map((i) => i.updatedAt).reduce((x, y) => x.isAfter(y) ? x : y);
                final latestB = groupedInsights[b]!.map((i) => i.updatedAt).reduce((x, y) => x.isAfter(y) ? x : y);
                return latestB.compareTo(latestA); 
              });

              List<List<InsightModel>> globalGroupedList = [];
              if (hasMyInsights) {
                globalGroupedList.add(myInsights!..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)));
              }
              for (var uId in sortedUserIds) {
                globalGroupedList.add(groupedInsights[uId]!..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)));
              }

              return ListView.builder(
                padding: EdgeInsets.only(left: 24, right: 8),
                scrollDirection: Axis.horizontal,
                itemCount: sortedUserIds.length + 1, 
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildMyInsightBox(context, hasMyInsights, globalGroupedList);
                  }

                  final userId = sortedUserIds[index - 1];
                  final userInsights = groupedInsights[userId]!;
                  final userIndex = hasMyInsights ? index : index - 1;
                  return _buildUserInsightBubble(context, userInsights, globalGroupedList, userIndex);
                },
              );
            },
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMyInsightBox(BuildContext context, bool hasMyInsights, List<List<InsightModel>> globalGroupedList) {
    final user = FirebaseAuth.instance.currentUser;
    int unseenCount = 0;
    if (hasMyInsights && user != null) {
      unseenCount = globalGroupedList.first.where((i) => !i.seenBy.contains(user.uid)).length;
    }
    bool hasUnseen = unseenCount > 0;
    
    return Container(
      margin: EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (hasMyInsights) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ViewInsightScreen(
                          userInsightsGroups: globalGroupedList,
                          initialUserIndex: 0,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInsightScreen()));
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: (hasMyInsights && hasUnseen) 
                          ? SweepGradient(
                              colors: [
                                AppColors.gradientEnd,
                                AppColors.gradientStart,
                                AppColors.gradientEnd,
                                AppColors.gradientStart,
                                AppColors.gradientEnd,
                              ],
                            )
                          : null,
                      color: (hasMyInsights && hasUnseen) ? null : Theme.of(context).dividerColor,
                    ),
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).scaffoldBackgroundColor,
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        backgroundImage: user?.photoURL != null ? CachedNetworkImageProvider(user!.photoURL!) : null,
                        child: user?.photoURL == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), size: 40) : null,
                      ),
                    ),
                ),
              ),
              if (!hasMyInsights)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInsightScreen()));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.gradientEnd,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.add, color: Colors.white, size: 16),
                    ),
                  ),
                )
              else if (hasUnseen)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.gradientEnd,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    padding: EdgeInsets.all(4),
                    child: Text(
                      unseenCount.toString(),
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
            SizedBox(height: 6),
            Text(
              hasMyInsights ? 'My Insight' : 'Add Insight',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
            ),
          ],
        ),
    );
  }

  Widget _buildUserInsightBubble(BuildContext context, List<InsightModel> userInsights, List<List<InsightModel>> globalGroupedList, int userIndex) {
    final authorName = ContactCacheService().getContactName(userInsights.first.authorUid, userInsights.first.authorName);
    final authorPhotoUrl = userInsights.first.authorPhotoUrl;
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    int unseenCount = 0;
    if (currentUserId != null) {
      unseenCount = userInsights.where((insight) => !insight.seenBy.contains(currentUserId)).length;
    }
    bool hasUnseen = unseenCount > 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewInsightScreen(
              userInsightsGroups: globalGroupedList,
              initialUserIndex: userIndex,
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasUnseen 
                        ? SweepGradient(
                            colors: [
                              AppColors.gradientEnd,
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                            ],
                          )
                        : null,
                    color: hasUnseen ? null : Theme.of(context).dividerColor,
                  ),
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      backgroundImage: authorPhotoUrl != null ? CachedNetworkImageProvider(authorPhotoUrl) : null,
                      child: authorPhotoUrl == null ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), size: 40) : null,
                    ),
                  ),
                ),
                if (hasUnseen)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.gradientEnd,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      padding: EdgeInsets.all(4),
                      child: Text(
                        unseenCount.toString(),
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 6),
            SizedBox(
              width: 90,
              child: Text(
                authorName.split(' ').first,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasUnseen ? FontWeight.w600 : FontWeight.normal,
                  color: hasUnseen ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
