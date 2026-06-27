import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final InsightService _insightService = InsightService();

  int _selectedColor = 0xFF2A3441; // Default dark theme
  bool _isPublishing = false;

  final List<int> _themeColors = [
    0xFF2A3441, // Dark Blue/Grey
    0xFF1B5E20, // Forest Green
    0xFF4A148C, // Deep Purple
    0xFFB71C1C, // Crimson
    0xFFE65100, // Deep Orange
    0xFF01579B, // Ocean Blue
  ];

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
        themeColor: _selectedColor,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 3)),
      );

      await _insightService.createInsight(insight);
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish insight: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(_selectedColor),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Add Insight', style: TextStyle(color: Colors.white)),
        actions: [
          if (_isPublishing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _publishInsight,
              child: const Text(
                'Publish',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Insight Title...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bodyController,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.5,
                        color: Colors.white,
                      ),
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'What did you learn from the Word today?\n\n(Tip: Type a scripture like Romans 8:1-4 to automatically link it!)',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              color: Colors.black12,
              child: Row(
                children: [
                  const Text('Theme:', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _themeColors.map((color) {
                          final isSelected = _selectedColor == color;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = color;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
