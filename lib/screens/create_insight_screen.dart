import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';

class CreateInsightScreen extends StatefulWidget {
  const CreateInsightScreen({super.key});

  @override
  State<CreateInsightScreen> createState() => _CreateInsightScreenState();
}

class _CreateInsightScreenState extends State<CreateInsightScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final InsightService _insightService = InsightService();

  bool _isPublishing = false;
  bool _isSuccess = false;

  Future<void> _publishInsight() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title and some insights.')),
      );
      return;
    }

    setState(() {
      _isPublishing = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final now = DateTime.now();
      final insight = InsightModel(
        id: const Uuid().v4(),
        authorUid: user.uid,
        authorName: user.displayName ?? 'Believer',
        authorPhotoUrl: user.photoURL,
        title: title,
        body: body,
        themeId: 'theme_0', // Default fallback
        createdAt: now,
        updatedAt: now,
        expiresAt: now.add(const Duration(days: 3)),
      );

      _insightService.createInsight(insight); 
      
      // Artificial delay so the user sees it "loading"
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _isSuccess = true;
        });
        
        // Wait briefly so the user sees the 'good' checkmark
        await Future.delayed(const Duration(milliseconds: 600));

        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish insight: $e')),
        );
        setState(() {
          _isPublishing = false;
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
        title: Text('Add Insight', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87))),
        actions: [
          if (_isSuccess)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.check_circle, color: AppColors.gradientEnd, size: 28),
            )
          else if (_isPublishing)
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
              onPressed: _publishInsight,
              child: Text(
                'Publish',
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
                    hintText: 'Type your insight...',
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
