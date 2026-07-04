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
        expiresAt: now.add(const Duration(days: 3)),
      );

      _insightService.createInsight(insight); 
      
      // Artificial delay so the user sees it "loading"
      await Future.delayed(const Duration(milliseconds: 1500));
      
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Add Insight', style: TextStyle(color: Colors.black87)),
        actions: [
          if (_isSuccess)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.check_circle, color: Colors.black, size: 28),
            )
          else if (_isPublishing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _publishInsight,
              child: const Text(
                'Publish',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
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
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bodyController,
                maxLines: null,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type your insight...',
                  hintStyle: TextStyle(
                    color: Colors.black38,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
