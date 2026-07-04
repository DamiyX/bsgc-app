import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../utils/scripture_parser.dart';
import '../widgets/bible_verse_bottom_sheet.dart';
import 'my_insights_screen.dart';

import 'dart:ui' as ui;

class ViewInsightScreen extends StatefulWidget {
  final List<List<InsightModel>> userInsightsGroups;
  final int initialUserIndex;

  const ViewInsightScreen({
    super.key,
    required this.userInsightsGroups,
    required this.initialUserIndex,
  });

  @override
  State<ViewInsightScreen> createState() => _ViewInsightScreenState();
}

class _ViewInsightScreenState extends State<ViewInsightScreen> {
  late PageController _userPageController;
  late List<int> _insightIndices;
  final FlutterTts _flutterTts = FlutterTts();
  String? _playingInsightId;

  @override
  void initState() {
    super.initState();
    _userPageController = PageController(initialPage: widget.initialUserIndex);
    _insightIndices = List.filled(widget.userInsightsGroups.length, 0);
    _initTts();
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _playingInsightId = null);
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _userPageController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(InsightModel insight) async {
    if (_playingInsightId == insight.id) {
      await _flutterTts.stop();
      if (mounted) setState(() => _playingInsightId = null);
    } else {
      await _flutterTts.stop();
      if (mounted) setState(() => _playingInsightId = insight.id);
      await _flutterTts.speak("${insight.title}. ${insight.body}");
    }
  }

  void _nextInsight(int userIndex) {
    setState(() {
      if (_insightIndices[userIndex] < widget.userInsightsGroups[userIndex].length - 1) {
        _insightIndices[userIndex]++;
      } else {
        if (userIndex < widget.userInsightsGroups.length - 1) {
          _userPageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
        } else {
          Navigator.pop(context);
        }
      }
    });
  }

  void _previousInsight(int userIndex) {
    setState(() {
      if (_insightIndices[userIndex] > 0) {
        _insightIndices[userIndex]--;
      } else {
        if (userIndex > 0) {
          _userPageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Transparent to show blurred background
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.2)), // Slight dark tint
            ),
          ),
          PageView.builder(
            controller: _userPageController,
            itemCount: widget.userInsightsGroups.length,
            itemBuilder: (context, userIndex) {
                final insights = widget.userInsightsGroups[userIndex];
                final insightIndex = _insightIndices[userIndex];
                final insight = insights[insightIndex];
                final isPlaying = _playingInsightId == insight.id;

                return _ViewInsightPage(
                  insight: insight,
                  insightIndex: insightIndex,
                  totalInsights: insights.length,
                  isPlaying: isPlaying,
                  onTogglePlay: () => _togglePlay(insight),
                  onPrevious: () => _previousInsight(userIndex),
                  onNext: () => _nextInsight(userIndex),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ViewInsightPage extends StatefulWidget {
  final InsightModel insight;
  final int insightIndex;
  final int totalInsights;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _ViewInsightPage({
    required this.insight,
    required this.insightIndex,
    required this.totalInsights,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<_ViewInsightPage> createState() => _ViewInsightPageState();
}

class _ViewInsightPageState extends State<_ViewInsightPage> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commentController = TextEditingController();
  final InsightService _insightService = InsightService();
  InsightCommentModel? _replyingTo;
  bool _isLiked = false;
  double _dismissOffset = 0.0;

  late AnimationController _commentsAnimController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !widget.insight.seenBy.contains(user.uid)) {
      _insightService.markAsSeen(widget.insight.id, user.uid);
    }
    
    _commentsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _commentsAnimController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _commentsAnimController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _commentsAnimController.dispose();
    _scrollController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _toggleComments() {
    if (_commentsAnimController.isCompleted) {
      _commentsAnimController.reverse();
      FocusScope.of(context).unfocus();
    } else {
      _commentsAnimController.forward();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_commentsAnimController.isAnimating) return;
    
    final dy = details.primaryDelta!;
    
    // If pulling down and comments are closed, handle dismiss
    if (_commentsAnimController.isDismissed && (dy > 0 || _dismissOffset > 0)) {
      setState(() {
        _dismissOffset += dy;
        if (_dismissOffset < 0) _dismissOffset = 0;
      });
      return;
    }
    
    // Otherwise, handle comments (pulling up)
    final delta = -dy / MediaQuery.of(context).size.height;
    _commentsAnimController.value += delta;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dismissOffset > 0) {
      if (_dismissOffset > 150 || details.primaryVelocity! > 300) {
        Navigator.pop(context);
      } else {
        setState(() {
          _dismissOffset = 0;
        });
      }
      return;
    }
    
    if (_commentsAnimController.isAnimating) return;
    
    final velocity = -details.primaryVelocity!; // negative because UP is negative dy
    
    if (velocity > 300) {
      _commentsAnimController.forward();
    } else if (velocity < -300) {
      _commentsAnimController.reverse();
      FocusScope.of(context).unfocus();
    } else if (_commentsAnimController.value > 0.5) {
      _commentsAnimController.forward();
    } else {
      _commentsAnimController.reverse();
      FocusScope.of(context).unfocus();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _submitDirectComment() async {
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
      replyToId: _replyingTo?.id,
      replyToName: _replyingTo?.authorName,
      createdAt: DateTime.now(),
    );

    _commentController.clear();
    setState(() => _replyingTo = null);
    
    await _insightService.addComment(widget.insight.id, comment);
    
    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 500), _scrollToBottom);
  }

  Widget _buildInsightBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.insight.title.isNotEmpty) ...[
          Text(
            widget.insight.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: RichText(
            text: TextSpan(
              children: ScriptureParser.parseText(
                text: widget.insight.body,
                defaultStyle: const TextStyle(
                  fontSize: 16, 
                  color: Colors.black87, 
                  height: 1.5,
                ),
                linkStyle: const TextStyle(
                  fontSize: 16, 
                  color: Colors.blueAccent, 
                  height: 1.5, 
                  fontWeight: FontWeight.bold, 
                  decoration: TextDecoration.underline
                ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingBottomBar() {
    final countStream = _insightService.getComments(widget.insight.id);
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withAlpha(0),
            Colors.white.withAlpha(200),
            Colors.white,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _toggleComments,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Add a comment...', style: TextStyle(color: Colors.black54)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined, color: Colors.black87),
            onPressed: () => setState(() => _isLiked = !_isLiked),
          ),
          const SizedBox(width: 4),
          StreamBuilder<List<InsightCommentModel>>(
            stream: countStream,
            builder: (context, snapshot) {
              final count = snapshot.hasData ? snapshot.data!.length : 0;
              return GestureDetector(
                onTap: _toggleComments,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      const Icon(Icons.keyboard_arrow_up, color: Colors.black87),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]
                    ],
                  ),
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildFacebookStyleComment(InsightCommentModel comment, List<InsightCommentModel> allComments, int depth) {
    final replies = allComments.where((c) => c.replyToId == comment.id).toList();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isLiked = comment.likedBy.contains(currentUserId);
    final likeCount = comment.likedBy.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0, bottom: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (depth > 0)
                Container(
                  width: 24,
                  height: 32,
                  margin: const EdgeInsets.only(right: 8, top: 4),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.black12, width: 2),
                      bottom: BorderSide(color: Colors.black12, width: 2),
                    ),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12)),
                  ),
                ),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey[300],
                backgroundImage: comment.authorPhotoUrl != null ? NetworkImage(comment.authorPhotoUrl!) : null,
                child: comment.authorPhotoUrl == null ? const Icon(Icons.person, size: 16, color: Colors.black54) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(comment.authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                          const SizedBox(height: 4),
                          Text(comment.body, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: Row(
                        children: [
                          Text(DateFormat('MMM d, h:mm a').format(comment.createdAt), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () => _insightService.toggleCommentLike(widget.insight.id, comment.id, currentUserId, !isLiked),
                            child: Row(
                              children: [
                                Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined, size: 14, color: isLiked ? Colors.black87 : Colors.black54),
                                if (likeCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text('$likeCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                                ]
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              setState(() => _replyingTo = comment);
                              if (_commentsAnimController.isDismissed) _toggleComments();
                            },
                            child: const Text('Reply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (replies.isNotEmpty)
          ...replies.map((reply) => _buildFacebookStyleComment(reply, allComments, depth + 1)),
      ],
    );
  }

  Widget _buildCommentInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 8, 
        bottom: MediaQuery.of(context).viewInsets.bottom + 16, 
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 4),
              child: Row(
                children: [
                  Text('Replying to ${_replyingTo!.authorName}', style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: const Icon(Icons.close, size: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _submitDirectComment(),
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    hintStyle: const TextStyle(color: Colors.black54),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submitDirectComment,
                child: const Icon(Icons.send, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSheet() {
    final countStream = _insightService.getComments(widget.insight.id);
    return GestureDetector(
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  const SizedBox(width: 8),
                  StreamBuilder<List<InsightCommentModel>>(
                    stream: countStream,
                    builder: (context, snapshot) {
                      final count = snapshot.hasData ? snapshot.data!.length : 0;
                      return Text('$count', style: const TextStyle(fontSize: 14, color: Colors.black54));
                    }
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: Colors.black12),
          Expanded(
            child: StreamBuilder<List<InsightCommentModel>>(
              stream: _insightService.getComments(widget.insight.id),
              builder: (context, snapshot) {
                final comments = snapshot.data ?? [];
                if (comments.isEmpty) {
                  return const Center(child: Text('No comments yet.', style: TextStyle(color: Colors.black54)));
                }
                
                // Group comments by replyToId for nested rendering
                final topLevelComments = comments.where((c) => c.replyToId == null).toList();
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: topLevelComments.length,
                  itemBuilder: (context, index) {
                    return _buildFacebookStyleComment(topLevelComments[index], comments, 0);
                  },
                );
              }
            ),
          ),
          _buildCommentInputArea(),
        ],
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMyInsight = widget.insight.authorUid == FirebaseAuth.instance.currentUser?.uid;

    final mainContent = SafeArea(
      child: Transform.translate(
        offset: Offset(0, _dismissOffset),
        child: GestureDetector(
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: _handleDragEnd,
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: List.generate(widget.totalInsights, (idx) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: idx <= widget.insightIndex ? Colors.black87 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            
            // Author Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: widget.insight.authorPhotoUrl != null ? NetworkImage(widget.insight.authorPhotoUrl!) : null,
                        child: widget.insight.authorPhotoUrl == null ? const Icon(Icons.person, color: Colors.black45) : null,
                      ),
                      if (isMyInsight)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => MyInsightsScreen()));
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.insight.authorName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                        ),
                        Text(
                          DateFormat('MMM d, h:mm a').format(widget.insight.createdAt),
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(widget.isPlaying ? Icons.pause_circle_filled : Icons.volume_up, color: Colors.black87),
                    onPressed: widget.onTogglePlay,
                  ),
                ],
              ),
            ),
            
            // Main Content Area
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      bool shouldOpen = false;
                      if (notification is OverscrollNotification && notification.overscroll > 0) {
                        shouldOpen = true;
                      } else if (notification is ScrollUpdateNotification && notification.metrics.pixels > notification.metrics.maxScrollExtent + 30) {
                        shouldOpen = true;
                      }
                      if (shouldOpen && _commentsAnimController.isDismissed) {
                        _toggleComments();
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 100),
                      child: _buildInsightBody(),
                    ),
                  ),
                  // Left Tap Zone
                  Positioned(
                    left: 0, top: 0, bottom: 0, width: 100,
                    child: GestureDetector(
                      onTap: widget.onPrevious,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                  // Right Tap Zone
                  Positioned(
                    right: 0, top: 0, bottom: 0, width: 100,
                    child: GestureDetector(
                      onTap: widget.onNext,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                  // Floating Bottom Bar
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: _buildFloatingBottomBar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _commentsAnimController,
          builder: (context, child) {
            final double value = _commentsAnimController.value;
            return Transform(
              transform: Matrix4.identity()
                ..translate(0.0, MediaQuery.of(context).size.height * -0.03 * value)
                ..scale(_scaleAnimation.value)
                ..translate(0.0, MediaQuery.of(context).size.height * 0.03 * value),
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(value * 24),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            );
          },
          child: mainContent,
        ),
        // Dark overlay when comments open (optional, but looks nice)
        AnimatedBuilder(
          animation: _commentsAnimController,
          builder: (context, child) {
            if (_commentsAnimController.isDismissed) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () {
                if (_commentsAnimController.isCompleted) {
                  _toggleComments();
                }
              },
              child: Container(
                color: Colors.black.withOpacity(_commentsAnimController.value * 0.5),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: _commentsAnimController,
          builder: (context, child) {
            final sheetHeight = MediaQuery.of(context).size.height * 0.75;
            return Positioned(
              bottom: -sheetHeight * _slideAnimation.value,
              left: 0,
              right: 0,
              height: sheetHeight,
              child: child!,
            );
          },
          child: _buildCommentsSheet(),
        ),
      ],
    );
  }
}
