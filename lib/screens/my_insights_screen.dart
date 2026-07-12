import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import 'create_insight_screen.dart';
import 'view_insight_screen.dart';

class MyInsightsScreen extends StatelessWidget {
  MyInsightsScreen({super.key});

  final InsightService _insightService = InsightService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  void _deleteInsight(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Insight?'),
        content: const Text('This will permanently delete this insight.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _insightService.deleteInsight(id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Insight deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'My Insights',
          style: TextStyle(color: Colors.black87),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<InsightModel>>(
                stream: _insightService.getActiveInsightsForUser(
                  _currentUserId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.gradientEnd),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading insights'));
                  }
                  final insights = snapshot.data ?? [];

                  if (insights.isEmpty) {
                    return const Center(
                      child: Text(
                        'You have no active notes.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    itemCount: insights.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 76),
                    itemBuilder: (context, index) {
                      final insight = insights[index];
                      final user = FirebaseAuth.instance.currentUser;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  ViewInsightScreen(
                                    userInsightsGroups: [insights],
                                    initialUserIndex: 0,
                                  ),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                AppColors.gradientEnd,
                                AppColors.gradientStart,
                                AppColors.gradientEnd,
                                AppColors.gradientStart,
                                AppColors.gradientEnd,
                              ],
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                              child: user?.photoURL == null ? const Icon(Icons.person, color: Colors.black45) : null,
                            ),
                          ),
                        ),
                        title: Text(
                          insight.title.isEmpty ? 'Untitled Note' : insight.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(
                                DateFormat('MMM d, HH:mm').format(insight.createdAt),
                                style: const TextStyle(color: Colors.black54, fontSize: 13),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.visibility_outlined, size: 14, color: Colors.black54),
                              const SizedBox(width: 4),
                              Text('${insight.seenBy.length}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                              const SizedBox(width: 12),
                              const Icon(Icons.favorite_border, size: 14, color: Colors.black54),
                              const SizedBox(width: 4),
                              Text('${insight.likedBy.length}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                            ],
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.black54),
                          onSelected: (val) {
                            if (val == 'delete') {
                              _deleteInsight(context, insight.id);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Bottom area with encryption text
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.gradientEnd),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your insights are end-to-end encrypted. They disappear after 3 days.',
                      style: TextStyle(color: Colors.black54, fontSize: 11),
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
        backgroundColor: AppColors.gradientEnd,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateInsightScreen()),
          );
        },
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}
