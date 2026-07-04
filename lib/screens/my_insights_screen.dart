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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insight deleted')),
        );
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
        title: const Text('My Insights', style: TextStyle(color: Colors.black87)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: const [
                  Icon(Icons.lock_outline, size: 16, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your insights are end-to-end encrypted. They will disappear after 3 days.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<InsightModel>>(
                stream: _insightService.getActiveInsightsForUser(_currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.black87));
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading insights'));
                  }
                  final insights = snapshot.data ?? [];

                  if (insights.isEmpty) {
                    return const Center(
                      child: Text('You have no active insights.', style: TextStyle(color: Colors.black54)),
                    );
                  }

                  return ListView.builder(
                    itemCount: insights.length,
                    itemBuilder: (context, index) {
                      final insight = insights[index];
                      final user = FirebaseAuth.instance.currentUser;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                          child: user?.photoURL == null ? const Icon(Icons.person, color: Colors.black45) : null,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (context, animation, secondaryAnimation) => ViewInsightScreen(
                                userInsightsGroups: [insights],
                                initialUserIndex: 0,
                              ),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        title: Text(
                          insight.title.isEmpty ? 'Untitled Insight' : insight.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            DateFormat('MMM d, h:mm a').format(insight.createdAt),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StreamBuilder<List<InsightCommentModel>>(
                              stream: _insightService.getComments(insight.id),
                              builder: (context, commentSnap) {
                                final count = commentSnap.hasData ? commentSnap.data!.length : 0;
                                return Row(
                                  children: [
                                    const Icon(Icons.thumb_up_alt_outlined, size: 16, color: Colors.black54),
                                    const SizedBox(width: 4),
                                    Text('$count', style: const TextStyle(color: Colors.black54, fontSize: 13)), 
                                  ],
                                );
                              }
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
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
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black87,
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
