import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note_model.dart';
import '../services/note_service.dart';
import '../theme.dart';
import '../widgets/clickable_scripture_text.dart';

class ViewNoteScreen extends StatefulWidget {
  final NoteModel note;
  final NoteWriter noteWriter;

  ViewNoteScreen({super.key, required this.note, NoteWriter? noteWriter})
    : noteWriter = noteWriter ?? NoteService();

  @override
  State<ViewNoteScreen> createState() => _ViewNoteScreenState();
}

class _ViewNoteScreenState extends State<ViewNoteScreen> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  String? _titleError;
  String? _bodyError;

  // Undo/Redo controllers
  final UndoHistoryController _titleUndoController = UndoHistoryController();
  final UndoHistoryController _bodyUndoController = UndoHistoryController();

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

  Future<void> _saveChanges() async {
    if (_isSaving) return;

    final titleError = validateNoteTitle(_titleController.text);
    final bodyError = validateNoteBody(_bodyController.text);
    if (titleError != null || bodyError != null) {
      setState(() {
        _titleError = titleError;
        _bodyError = bodyError;
      });
      return;
    }

    final updatedNote = NoteModel(
      id: widget.note.id,
      authorUid: widget.note.authorUid,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      themeId: widget.note.themeId,
      createdAt: widget.note.createdAt,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _isSaving = true;
      _titleError = null;
      _bodyError = null;
    });

    try {
      await widget.noteWriter.saveNote(updatedNote);
      if (!mounted) return;
      setState(() {
        _isEditing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't save this note. Your changes are still here. Try again.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Save note',
                icon: Icon(Icons.check, color: AppColors.gradientEnd),
                onPressed: _saveChanges,
              ),
          ] else ...[
            IconButton(
              tooltip: 'Edit note',
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
                    key: const ValueKey('note-title-field'),
                    controller: _titleController,
                    undoController: _titleUndoController,
                    maxLength: noteTitleMaxLength,
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
                    ).copyWith(errorText: _titleError),
                    onChanged: (_) {
                      if (_titleError != null) {
                        setState(() => _titleError = null);
                      }
                    },
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: Focus(
                    onFocusChange: (hasFocus) {
                      if (hasFocus) setState(() => _isTitleFocused = false);
                    },
                    child: TextField(
                      key: const ValueKey('note-body-field'),
                      controller: _bodyController,
                      undoController: _bodyUndoController,
                      maxLength: noteBodyMaxLength,
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
                      ).copyWith(errorText: _bodyError),
                      onChanged: (_) {
                        if (_bodyError != null) {
                          setState(() => _bodyError = null);
                        }
                      },
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
