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
        color: Theme.of(context).cardColor,
        elevation: 0,
        margin: EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      insight.title.isEmpty ? 'Untitled Insight' : insight.title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                        size: 20,
                      ),
                      onSelected: (val) {
                        if (val == 'delete') {
                          onDelete();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              ClickableScriptureText(
                text: insight.body,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4, fontSize: 14),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Text(
                DateFormat('MMM d, yyyy').format(insight.createdAt),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
