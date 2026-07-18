import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/note_model.dart';
import '../services/note_service.dart';
import 'view_note_screen.dart';

class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({super.key});

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final NoteService _noteService = NoteService();

  bool _isSaving = false;
  bool _isSuccess = false;

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title and a note.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final now = DateTime.now();
      final note = NoteModel(
        id: const Uuid().v4(),
        authorUid: user.uid,
        title: title,
        body: body,
        themeId: 'theme_0',
        createdAt: now,
        updatedAt: now,
      );

      // Await save
      await _noteService.saveNote(note);
      
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSuccess = true;
        });
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ViewNoteScreen(note: note)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save note: $e')),
        );
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
        title: Text('Create Note', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87))),
        actions: [
          if (_isSuccess)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onSurface, size: 28),
            )
          else if (_isSaving)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: AppColors.gradientEnd, strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveNote,
              child: Text(
                'Save',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                controller: _titleController,
                maxLines: null,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              SizedBox(height: 16),
              Expanded(
                child: TextField(
                  cursorColor: Theme.of(context).colorScheme.onSurface,
                  controller: _bodyController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                    fontSize: 16,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type your note...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
