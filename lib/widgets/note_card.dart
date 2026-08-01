import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note_model.dart';
import '../screens/view_note_screen.dart';
import 'clickable_scripture_text.dart';

class NoteCard extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onDelete;
  final VoidCallback? onShare;
  final bool isGrid;

  const NoteCard({
    super.key,
    required this.note,
    required this.onDelete,
    this.onShare,
    this.isGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ViewNoteScreen(note: note)),
        );
      },
      child: Card(
        elevation: 0,
        color: Theme.of(context).cardColor,
        margin: isGrid ? EdgeInsets.zero : EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled Note' : note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 3,
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.54),
                        size: 20,
                      ),
                      onSelected: (val) {
                        if (val == 'delete') {
                          onDelete();
                        }
                        if (val == 'share') {
                          onShare?.call();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onShare != null)
                          const PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(Icons.ios_share_outlined),
                                SizedBox(width: 8),
                                Text('Share a copy'),
                              ],
                            ),
                          ),
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
              if (isGrid)
                Expanded(
                  child: ClickableScriptureText(
                    text: note.body,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                      fontSize: 14,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                ClickableScriptureText(
                  text: note.body,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
              if (!isGrid) SizedBox(height: 8),
              Text(
                DateFormat('MMM d, yyyy').format(note.updatedAt),
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
