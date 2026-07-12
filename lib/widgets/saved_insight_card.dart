import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../screens/view_insight_screen.dart';
import 'clickable_scripture_text.dart';

class SavedInsightCard extends StatelessWidget {
  final InsightModel insight;
  final VoidCallback onDelete;

  const SavedInsightCard({
    super.key,
    required this.insight,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Pass it to ViewInsightScreen as a single list of list
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewInsightScreen(
              userInsightsGroups: [[insight]],
              initialUserIndex: 0,
            ),
          ),
        );
      },
      child: Card(
        color: Colors.white,
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      insight.title.isEmpty ? 'Untitled Insight' : insight.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(Icons.bookmark_remove, color: Colors.black54, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 0, // In listview, we don't need Expanded here, we can just let it size naturally
                child: ClickableScriptureText(
                  text: insight.body,
                  style: TextStyle(color: Colors.grey[800], height: 1.4, fontSize: 14),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('MMM d, yyyy').format(insight.createdAt),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
