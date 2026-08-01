import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/note_model.dart';
import '../services/draft_service.dart';
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
  final DraftService _draftService = DraftService();
  Timer? _draftTimer;
  String? _draftUserId;
  bool _isRestoringDraft = false;
  bool _hasUserEdited = false;
  bool _isDraftFinalized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_scheduleDraftSave);
    _bodyController.addListener(_scheduleDraftSave);
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    _draftUserId = userId;
    final draft = await _draftService.loadComposerDraft(
      userId: userId,
      audience: ComposerDraftAudience.private,
    );
    if (!mounted || draft == null || _hasUserEdited) return;
    _isRestoringDraft = true;
    _titleController.text = draft.title;
    _bodyController.text = draft.body;
    _isRestoringDraft = false;
  }

  void _scheduleDraftSave() {
    if (_isRestoringDraft) return;
    _hasUserEdited = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _saveDraftNow);
  }

  Future<void> _saveDraftNow({bool showError = true}) async {
    if (_isDraftFinalized) return;
    final userId = _draftUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      await _draftService.saveComposerDraft(
        userId: userId,
        draft: ComposerDraft(
          title: _titleController.text,
          body: _bodyController.text,
          audience: ComposerDraftAudience.private,
        ),
      );
    } catch (_) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't save this local draft. Keep this screen open.",
            ),
          ),
        );
      }
    }
  }

  Future<void> _discardDraft() async {
    final hasText =
        _titleController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty;
    if (hasText) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard draft?'),
          content: const Text(
            'Your unsaved private reflection will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _draftTimer?.cancel();
    final userId = _draftUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await _draftService.clearComposerDraft(
        userId: userId,
        audience: ComposerDraftAudience.private,
      );
    }
    _titleController.clear();
    _bodyController.clear();
  }

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
      _draftTimer?.cancel();
      _isDraftFinalized = true;
      try {
        await _draftService.clearComposerDraft(
          userId: user.uid,
          audience: ComposerDraftAudience.private,
        );
      } catch (_) {
        // The note is already durable remotely; never turn a local cleanup
        // failure into a misleading save failure.
      }
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
          IconButton(
            tooltip: 'Discard draft',
            onPressed: _isSaving ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _saveNote,
              child: _isSaving
                  ? Semantics(
                      liveRegion: true,
                      label: 'Saving private note',
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
                maxLength: noteTitleMaxLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'A thought to return to',
                  border: OutlineInputBorder(),
                ),
                validator: validateNoteTitle,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                minLines: 10,
                maxLines: 20,
                maxLength: noteBodyMaxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Write freely. This is not shared with a group.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: validateNoteBody,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_saveDraftNow(showError: false));
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
