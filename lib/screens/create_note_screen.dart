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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Create Note', style: TextStyle(color: Colors.black87)),
        actions: [
          if (_isSuccess)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.check_circle, color: Colors.black, size: 28),
            )
          else if (_isSaving)
            const Padding(
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
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                cursorColor: Colors.black,
                controller: _titleController,
                maxLines: null,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    color: Colors.black38,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  cursorColor: Colors.black,
                  controller: _bodyController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type your note...',
                    hintStyle: TextStyle(
                      color: Colors.black38,
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
