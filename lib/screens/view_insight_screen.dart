import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../utils/scripture_parser.dart';
import '../widgets/bible_verse_bottom_sheet.dart';
import 'package:intl/intl.dart';

class ViewInsightScreen extends StatefulWidget {
  final List<InsightModel> insights;
  final int initialIndex;

  const ViewInsightScreen({
    super.key,
    required this.insights,
    required this.initialIndex,
  });

  @override
  State<ViewInsightScreen> createState() => _ViewInsightScreenState();
}

class _ViewInsightScreenState extends State<ViewInsightScreen> {
  late PageController _pageController;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _initTts();
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _togglePlay(String text) async {
    if (_isPlaying) {
      await _flutterTts.stop();
      setState(() {
        _isPlaying = false;
      });
    } else {
      setState(() {
        _isPlaying = true;
      });
      await _flutterTts.speak(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.insights.length,
        onPageChanged: (_) {
          _flutterTts.stop();
          setState(() {
            _isPlaying = false;
          });
        },
        itemBuilder: (context, index) {
          return _InsightPage(
            insight: widget.insights[index],
            isPlaying: _isPlaying,
            onPlayToggled: () => _togglePlay("${widget.insights[index].title}. ${widget.insights[index].body}"),
          );
        },
      ),
    );
  }
}

class _InsightPage extends StatefulWidget {
  final InsightModel insight;
  final bool isPlaying;
  final VoidCallback onPlayToggled;

  const _InsightPage({
    required this.insight,
    required this.isPlaying,
    required this.onPlayToggled,
  });

  @override
  State<_InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<_InsightPage> {
  final InsightService _insightService = InsightService();
  final TextEditingController _commentController = TextEditingController();

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final comment = InsightCommentModel(
      id: const Uuid().v4(),
      insightId: widget.insight.id,
      authorUid: user.uid,
      authorName: user.displayName ?? 'Believer',
      authorPhotoUrl: user.photoURL,
      body: text,
      createdAt: DateTime.now(),
    );

    _commentController.clear();
    await _insightService.addComment(widget.insight.id, comment);
  }

  Widget _buildRichText(String text, BuildContext context) {
    return RichText(
      text: TextSpan(
        children: ScriptureParser.parseText(
          text: text,
          defaultStyle: const TextStyle(fontSize: 18, color: Colors.white, height: 1.6),
          linkStyle: const TextStyle(fontSize: 18, color: Colors.orange, height: 1.6, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
          onReferenceTap: (reference) {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                child: BibleVerseBottomSheet(reference: reference),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(widget.insight.themeColor),
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: widget.insight.authorPhotoUrl != null ? NetworkImage(widget.insight.authorPhotoUrl!) : null,
                    child: widget.insight.authorPhotoUrl == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.insight.authorName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          DateFormat('MMM d, h:mm a').format(widget.insight.createdAt),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(widget.isPlaying ? Icons.pause_circle_filled : Icons.volume_up, color: Colors.white, size: 28),
                    onPressed: widget.onPlayToggled,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Content & Comments
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Insight Body
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.insight.title.isNotEmpty) ...[
                            Text(
                              widget.insight.title,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          _buildRichText(widget.insight.body, context),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Comments Section
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Comments',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<List<InsightCommentModel>>(
                            stream: _insightService.getComments(widget.insight.id),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox.shrink();
                              final comments = snapshot.data!;
                              if (comments.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Text('No comments yet. Be the first!', style: TextStyle(color: Colors.white54)),
                                );
                              }
                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: comments.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (context, i) {
                                  final comment = comments[i];
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundImage: comment.authorPhotoUrl != null ? NetworkImage(comment.authorPhotoUrl!) : null,
                                        child: comment.authorPhotoUrl == null ? const Icon(Icons.person, size: 16) : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  comment.authorName,
                                                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  DateFormat('MMM d').format(comment.createdAt),
                                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              comment.body,
                                              style: const TextStyle(color: Colors.white, fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          // Comment Input
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Add a comment...',
                                    hintStyle: const TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor: Colors.white12,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.white),
                                onPressed: _submitComment,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
