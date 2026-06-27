import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../screens/create_insight_screen.dart';
import '../screens/view_insight_screen.dart';
import 'package:intl/intl.dart';

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
          height: 180,
          child: StreamBuilder<List<InsightModel>>(
            stream: _insightService.getActiveInsights(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Error loading insights'));
              }

              final insights = snapshot.data ?? [];
              
              // We'll calculate width such that exactly 3.5 items fit on the screen
              // (24 padding left + 3.5 * width + 3.5 * spacing = screen width)
              // This is a rough estimation for "Snapchat style"
              final screenWidth = MediaQuery.of(context).size.width;
              // 24 for left padding
              final boxWidth = (screenWidth - 24) / 3.5;

              return ListView.builder(
                padding: const EdgeInsets.only(left: 24, right: 8),
                scrollDirection: Axis.horizontal,
                itemCount: insights.length + 1, // +1 for the 'Add Insight' box
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildAddInsightBox(context, boxWidth);
                  }

                  final insight = insights[index - 1];
                  return _buildInsightBox(context, insight, boxWidth, insights, index - 1);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAddInsightBox(BuildContext context, double width) {
    final user = FirebaseAuth.instance.currentUser;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInsightScreen()));
      },
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Middle-top placement for add status
            Align(
              alignment: const Alignment(0, -0.4),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                    child: user?.photoURL == null ? const Icon(Icons.person, color: Colors.black45) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.add, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Add Insight',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightBox(BuildContext context, InsightModel insight, double width, List<InsightModel> allInsights, int index) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewInsightScreen(
              insights: allInsights,
              initialIndex: index,
            ),
          ),
        );
      },
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Color(insight.themeColor),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: insight.authorPhotoUrl != null ? NetworkImage(insight.authorPhotoUrl!) : null,
                  child: insight.authorPhotoUrl == null ? const Icon(Icons.person, color: Colors.black45) : null,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0, left: 4, right: 4),
                child: Text(
                  insight.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
