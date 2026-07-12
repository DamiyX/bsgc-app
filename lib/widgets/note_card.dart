import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note_model.dart';
import '../screens/view_note_screen.dart';
import 'clickable_scripture_text.dart';

class NoteCard extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onDelete;
  final bool isGrid;

  const NoteCard({
    super.key,
    required this.note,
    required this.onDelete,
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
        color: Colors.grey[100],
        margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      style: const TextStyle(
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
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.black54,
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
              const SizedBox(height: 8),
              if (isGrid)
                Expanded(
                  child: ClickableScriptureText(
                    text: note.body,
                    style: TextStyle(
                      color: Colors.grey[800],
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
                    color: Colors.grey[800],
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
              if (!isGrid) const SizedBox(height: 8),
              Text(
                DateFormat('MMM d, yyyy').format(note.updatedAt),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
