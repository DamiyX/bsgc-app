import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../theme.dart';

class CreateInsightScreen extends StatefulWidget {
  const CreateInsightScreen({super.key});

  @override
  State<CreateInsightScreen> createState() => _CreateInsightScreenState();
}

class _CreateInsightScreenState extends State<CreateInsightScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final InsightService _insightService = InsightService();
  bool _isPublishing = false;

  Future<void> _publishInsight() async {
    if (_isPublishing || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in before sharing an Insight.')),
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
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This Insight could not be published. Check your connection and '
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share an Insight'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isPublishing ? null : _publishInsight,
              child: _isPublishing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publish'),
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
                  title: const Text('Study contacts'),
                  subtitle: const Text(
                    'Visible for 3 days to people connected through an '
                    'accepted study invitation. Publishing needs internet.',
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
                  if (text.isEmpty) return 'Give this Insight a short title.';
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
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
