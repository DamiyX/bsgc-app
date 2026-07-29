import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note_model.dart';
import '../services/note_service.dart';
import '../theme.dart';
import '../widgets/clickable_scripture_text.dart';

class ViewNoteScreen extends StatefulWidget {
  final NoteModel note;

  const ViewNoteScreen({super.key, required this.note});

  @override
  State<ViewNoteScreen> createState() => _ViewNoteScreenState();
}

class _ViewNoteScreenState extends State<ViewNoteScreen> {
  bool _isEditing = false;
  late TextEditingController _titleController;
  late TextEditingController _bodyController;

  // Undo/Redo controllers
  final UndoHistoryController _titleUndoController = UndoHistoryController();
  final UndoHistoryController _bodyUndoController = UndoHistoryController();

  final NoteService _noteService = NoteService();
  bool _isTitleFocused = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _bodyController = TextEditingController(text: widget.note.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _titleUndoController.dispose();
    _bodyUndoController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    final updatedNote = NoteModel(
      id: widget.note.id,
      authorUid: widget.note.authorUid,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      themeId: widget.note.themeId,
      createdAt: widget.note.createdAt,
      updatedAt: DateTime.now(),
    );
    // Fire and forget save
    _noteService.saveNote(updatedNote);

    if (mounted) {
      setState(() {
        _isEditing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Note saved!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.87),
        ),
        actions: [
          if (_isEditing) ...[
            // Undo/Redo buttons
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _isTitleFocused
                  ? _titleUndoController
                  : _bodyUndoController,
              builder: (context, value, child) {
                return Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.undo),
                      onPressed: value.canUndo
                          ? () {
                              if (_isTitleFocused) {
                                _titleUndoController.undo();
                              } else {
                                _bodyUndoController.undo();
                              }
                            }
                          : null,
                    ),
                    IconButton(
                      icon: Icon(Icons.redo),
                      onPressed: value.canRedo
                          ? () {
                              if (_isTitleFocused) {
                                _titleUndoController.redo();
                              } else {
                                _bodyUndoController.redo();
                              }
                            }
                          : null,
                    ),
                  ],
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.check, color: AppColors.gradientEnd),
              onPressed: _saveChanges,
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                Icons.edit,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.87),
              ),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isEditing) ...[
                Text(
                  _titleController.text.isEmpty
                      ? 'Untitled Note'
                      : _titleController.text,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.87),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  DateFormat('MMM d, yyyy').format(widget.note.updatedAt),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: ClickableScriptureText(
                      text: _bodyController.text,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.87),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Focus(
                  onFocusChange: (hasFocus) {
                    if (hasFocus) setState(() => _isTitleFocused = true);
                  },
                  child: TextField(
                    controller: _titleController,
                    undoController: _titleUndoController,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.87),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Note Title',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: Focus(
                    onFocusChange: (hasFocus) {
                      if (hasFocus) setState(() => _isTitleFocused = false);
                    },
                    child: TextField(
                      controller: _bodyController,
                      undoController: _bodyUndoController,
                      maxLines: null,
                      expands: true,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.87),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Write your thoughts...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
