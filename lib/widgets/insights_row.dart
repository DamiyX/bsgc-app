import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../screens/create_insight_screen.dart';
import '../screens/view_insight_screen.dart';
import '../screens/my_insights_screen.dart';
import '../theme.dart';

class InsightsRow extends StatelessWidget {
  final InsightService _insightService = InsightService();

  InsightsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Text(
            'Insights',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        SizedBox(
          height: 110,
          child: StreamBuilder<List<InsightModel>>(
            stream: _insightService.getActiveInsights(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Error loading insights'));
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
                final latestA = groupedInsights[a]!.map((i) => i.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
                final latestB = groupedInsights[b]!.map((i) => i.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
                return latestB.compareTo(latestA); 
              });

              List<List<InsightModel>> globalGroupedList = [];
              if (hasMyInsights) {
                globalGroupedList.add(myInsights!..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
              }
              for (var uId in sortedUserIds) {
                globalGroupedList.add(groupedInsights[uId]!..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(left: 24, right: 8),
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
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMyInsightBox(BuildContext context, bool hasMyInsights, List<List<InsightModel>> globalGroupedList) {
    final user = FirebaseAuth.instance.currentUser;
    bool hasUnseen = true; // Mocked
    
    return Container(
      margin: const EdgeInsets.only(right: 16),
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
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: (hasMyInsights && hasUnseen) 
                        ? const SweepGradient(
                            colors: [
                              AppColors.gradientEnd,
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                            ],
                          )
                        : null,
                    border: (hasMyInsights && hasUnseen) ? null : Border.all(color: Colors.black12, width: 2),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null ? const Icon(Icons.person, color: Colors.black45, size: 30) : null,
                    ),
                  ),
                ),
              ),
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
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.add, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
            const SizedBox(height: 6),
            Text(
              hasMyInsights ? 'My Insight' : 'Add Insight',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
    );
  }

  Widget _buildUserInsightBubble(BuildContext context, List<InsightModel> userInsights, List<List<InsightModel>> globalGroupedList, int userIndex) {
    final authorName = userInsights.first.authorName;
    final authorPhotoUrl = userInsights.first.authorPhotoUrl;
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    bool hasUnseen = false;
    if (currentUserId != null) {
      hasUnseen = userInsights.any((insight) => !insight.seenBy.contains(currentUserId));
    }

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
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnseen 
                    ? const SweepGradient(
                        colors: [
                          AppColors.gradientEnd,
                          AppColors.gradientStart,
                          AppColors.gradientEnd,
                          AppColors.gradientStart,
                          AppColors.gradientEnd,
                        ],
                      )
                    : null,
                border: hasUnseen ? null : Border.all(color: Colors.black26, width: 2),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: authorPhotoUrl != null ? NetworkImage(authorPhotoUrl) : null,
                  child: authorPhotoUrl == null ? const Icon(Icons.person, color: Colors.black45, size: 30) : null,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 74,
              child: Text(
                authorName.split(' ').first,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasUnseen ? FontWeight.w600 : FontWeight.normal,
                  color: hasUnseen ? Colors.black87 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
