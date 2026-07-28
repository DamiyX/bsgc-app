import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/note_model.dart';
import '../services/note_service.dart';
import '../theme.dart';
import 'view_note_screen.dart';

class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({super.key});

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final NoteService _noteService = NoteService();
  bool _isSaving = false;

  Future<void> _saveNote() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in before saving a note.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();
    final note = NoteModel(
      id: const Uuid().v4(),
      authorUid: user.uid,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      themeId: 'theme_0',
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _noteService.saveNote(note);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ViewNoteScreen(note: note)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This note could not be saved. Keep this screen open and try '
              'again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<BraidSemanticColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private note'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _saveNote,
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Card(
                color: semantic.privateAudience.withValues(alpha: 0.1),
                child: ListTile(
                  leading: Icon(
                    Icons.lock_outline_rounded,
                    color: semantic.privateAudience,
                  ),
                  title: const Text('Only me'),
                  subtitle: const Text(
                    'Private to your account. Existing notes remain available '
                    'from the device cache when you lose connection.',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'A thought to return to',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Give this note a short title.';
                  if (text.length > 160) {
                    return 'Use no more than 160 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                minLines: 10,
                maxLines: 20,
                maxLength: 50000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Write freely. This is not shared with a group.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Write something to save.';
                  if (text.length > 50000) {
                    return 'Use no more than 50,000 characters.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
