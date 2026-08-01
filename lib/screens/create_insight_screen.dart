import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/insight_model.dart';
import '../services/draft_service.dart';
import '../services/insight_service.dart';
import '../theme.dart';

class CreateInsightScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialBody;

  const CreateInsightScreen({super.key, this.initialTitle, this.initialBody});

  @override
  State<CreateInsightScreen> createState() => _CreateInsightScreenState();
}

class _CreateInsightScreenState extends State<CreateInsightScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final InsightService _insightService = InsightService();
  final DraftService _draftService = DraftService();
  Timer? _draftTimer;
  String? _draftUserId;
  bool _isRestoringDraft = false;
  bool _hasUserEdited = false;
  bool _isDraftFinalized = false;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_scheduleDraftSave);
    _bodyController.addListener(_scheduleDraftSave);
    if (widget.initialTitle != null || widget.initialBody != null) {
      _isRestoringDraft = true;
      _titleController.text = widget.initialTitle ?? '';
      _bodyController.text = widget.initialBody ?? '';
      _isRestoringDraft = false;
    } else {
      _restoreDraft();
    }
  }

  Future<void> _restoreDraft() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    _draftUserId = userId;
    final draft = await _draftService.loadComposerDraft(
      userId: userId,
      audience: ComposerDraftAudience.contacts,
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
          audience: ComposerDraftAudience.contacts,
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
            'Your unsent contact reflection will be removed.',
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
        audience: ComposerDraftAudience.contacts,
      );
    }
    _titleController.clear();
    _bodyController.clear();
  }

  Future<void> _publishInsight() async {
    if (_isPublishing || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in before sharing a reflection.')),
      );
      return;
    }

    setState(() => _isPublishing = true);
    try {
      final now = DateTime.now();
      await _insightService.createInsight(
        InsightModel(
          id: const Uuid().v4(),
          authorUid: user.uid,
          authorName: user.displayName ?? 'Braid member',
          authorPhotoUrl: user.photoURL,
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          themeId: 'theme_0',
          createdAt: now,
          updatedAt: now,
          expiresAt: now.add(const Duration(days: 3)),
        ),
      );
      _draftTimer?.cancel();
      _isDraftFinalized = true;
      try {
        await _draftService.clearComposerDraft(
          userId: user.uid,
          audience: ComposerDraftAudience.contacts,
        );
      } catch (_) {
        // Publishing already succeeded; local draft cleanup must not make the
        // UI report a false publish failure.
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This reflection could not be shared. Check your connection and '
              'try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<BraidSemanticColors>()!;
    final isJournalCopy =
        widget.initialTitle != null || widget.initialBody != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share a reflection'),
        actions: [
          IconButton(
            tooltip: 'Discard draft',
            onPressed: _isPublishing ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isPublishing ? null : _publishInsight,
              child: _isPublishing
                  ? Semantics(
                      liveRegion: true,
                      label: 'Sharing reflection',
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Text('Share'),
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
                color: semantic.contactsAudience.withValues(alpha: 0.1),
                child: ListTile(
                  leading: Icon(
                    Icons.people_outline_rounded,
                    color: semantic.contactsAudience,
                  ),
                  title: Text(
                    isJournalCopy ? 'Review a journal copy' : 'Study contacts',
                  ),
                  subtitle: Text(
                    isJournalCopy
                        ? 'This copy stays private until you choose to share it. Shared reflections are visible for 3 days and need internet.'
                        : 'Visible for 3 days to people connected through an accepted study invitation. Sharing needs internet.',
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
                  hintText: 'What stayed with you?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Give this reflection a short title.';
                  }
                  if (text.length > 160) {
                    return 'Use no more than 160 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                minLines: 8,
                maxLines: 16,
                maxLength: 12000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reflection',
                  hintText:
                      'Share the Scripture, question, or understanding you '
                      'want your study contacts to sit with.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Write the reflection to share.';
                  if (text.length > 12000) {
                    return 'Use no more than 12,000 characters.';
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
    _draftTimer?.cancel();
    unawaited(_saveDraftNow(showError: false));
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
