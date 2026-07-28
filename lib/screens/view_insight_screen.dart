import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/insight_model.dart';
import '../services/insight_service.dart';
import '../services/notification_service.dart';
import '../widgets/clickable_scripture_text.dart';
import 'my_insights_screen.dart';
import 'create_insight_screen.dart';
import '../services/contact_cache_service.dart';
import '../theme.dart';
import '../widgets/report_dialog.dart';
import '../widgets/braid_media.dart';

import 'dart:ui' as ui;

enum TtsState { playing, paused, stopped }

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
  TtsState _ttsState = TtsState.stopped;

  @override
  void initState() {
    super.initState();
    _userPageController = PageController(initialPage: widget.initialUserIndex);
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _insightIndices = List.generate(widget.userInsightsGroups.length, (i) {
      if (currentUserId != null) {
        final firstUnseen = widget.userInsightsGroups[i].indexWhere((insight) => !insight.seenBy.contains(currentUserId));
        if (firstUnseen != -1) return firstUnseen;
      }
      return 0;
    });

    _initTts();
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _playingInsightId = null;
          _ttsState = TtsState.stopped;
        });
      }
    });

    _flutterTts.setPauseHandler(() {
      if (mounted) setState(() => _ttsState = TtsState.paused);
    });

    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _ttsState = TtsState.playing);
    });

    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _playingInsightId = null;
          _ttsState = TtsState.stopped;
        });
      }
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
      if (_ttsState == TtsState.playing) {
        await _flutterTts.pause();
        if (mounted) setState(() => _ttsState = TtsState.paused);
      } else if (_ttsState == TtsState.paused) {
        if (mounted) setState(() => _ttsState = TtsState.playing);
        await _flutterTts.speak("${insight.title}. ${insight.body}");
      } else {
        if (mounted) setState(() => _ttsState = TtsState.playing);
        await _flutterTts.speak("${insight.title}. ${insight.body}");
      }
    } else {
      await _flutterTts.stop();

      try {
        final prefs = await SharedPreferences.getInstance();
        final voiceName = prefs.getString('tts_voice_name');
        final voiceLocale = prefs.getString('tts_voice_locale');
        if (voiceName != null && voiceLocale != null) {
          await _flutterTts.setVoice({
            "name": voiceName,
            "locale": voiceLocale,
          });
        }
      } catch (e) {
        debugPrint('Error loading TTS voice: $e');
      }

      if (mounted) {
        setState(() {
          _playingInsightId = insight.id;
          _ttsState = TtsState.playing;
        });
      }
      await _flutterTts.speak("${insight.title}. ${insight.body}");
    }
  }

  void _nextInsight(int userIndex) {
    setState(() {
      if (_insightIndices[userIndex] <
          widget.userInsightsGroups[userIndex].length - 1) {
        _insightIndices[userIndex]++;
      } else {
        if (userIndex < widget.userInsightsGroups.length - 1) {
          _userPageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeIn,
          );
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
          _userPageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeIn,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.transparent, // Transparent to show blurred background
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
              ), // Slight dark tint
            ),
          ),
          PageView.builder(
            controller: _userPageController,
            itemCount: widget.userInsightsGroups.length,
            itemBuilder: (context, userIndex) {
              final insights = widget.userInsightsGroups[userIndex];
              final insightIndex = _insightIndices[userIndex];
              final insight = insights[insightIndex];
              final isCurrent = _playingInsightId == insight.id;
              final currentTtsState = isCurrent ? _ttsState : TtsState.stopped;

              return _ViewInsightPage(
                key: ValueKey(insight.id),
                insight: insight,
                insightIndex: insightIndex,
                totalInsights: insights.length,
                ttsState: currentTtsState,
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
  final TtsState ttsState;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _ViewInsightPage({
    super.key,
    required this.insight,
    required this.insightIndex,
    required this.totalInsights,
    required this.ttsState,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<_ViewInsightPage> createState() => _ViewInsightPageState();
}

class _ViewInsightPageState extends State<_ViewInsightPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commentController = TextEditingController();
  final InsightService _insightService = InsightService();
  InsightCommentModel? _replyingTo;
  bool _isLiked = false;
  bool _isSaved = false;
  double _dismissOffset = 0.0;
  bool _commentsVisible = false;

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
    
    _isLiked = user != null && widget.insight.likedBy.contains(user.uid);
    _loadReactionStatus();
    
    _checkSavedStatus();

    _commentsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(
        parent: _commentsAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _commentsAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _checkSavedStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final isSaved = await _insightService.isInsightSaved(user.uid, widget.insight.id);
      if (mounted) {
        setState(() {
          _isSaved = isSaved;
        });
      }
    }
  }

  Future<void> _loadReactionStatus() async {
    try {
      final isReacted = await _insightService.hasInsightReaction(
        widget.insight.id,
      );
      if (mounted) setState(() => _isLiked = isReacted);
    } catch (_) {
      // Legacy array state remains a read-only fallback during migration.
    }
  }

  @override
  void didUpdateWidget(_ViewInsightPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insight.id != widget.insight.id) {
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _isLiked = user != null && widget.insight.likedBy.contains(user.uid);
        _isSaved = false;
      });
      _loadReactionStatus();
      _checkSavedStatus();
    }
  }

  @override
  void dispose() {
    _commentsAnimController.dispose();
    _scrollController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _toggleComments() {
    setState(() => _commentsVisible = !_commentsVisible);
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

    final velocity =
        -details.primaryVelocity!; // negative because UP is negative dy

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
      replyToName: _replyingTo == null ? null : ContactCacheService().getContactName(_replyingTo!.authorUid, _replyingTo!.authorName),
      createdAt: DateTime.now(),
    );

    _commentController.clear();
    setState(() => _replyingTo = null);

    await _insightService.addComment(widget.insight.id, comment);

    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 500), _scrollToBottom);
  }

  Widget _buildInsightBody() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.insight.title.isNotEmpty) ...[
          Text(
            widget.insight.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
              height: 1.3,
            ),
          ),
          SizedBox(height: 16),
        ],

        Padding(
          padding: EdgeInsets.only(left: 12.0),
          child: ClickableScriptureText(
            text: widget.insight.body,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildFloatingBottomBar() {
    final countStream = _insightService.getComments(widget.insight.id);
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor.withAlpha(0),
            Theme.of(context).scaffoldBackgroundColor.withAlpha(200),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _toggleComments,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Add a comment...',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                          color: _isLiked ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          
                          if (!_isLiked) {
                            NotificationService().playActionSound();
                          }

                          setState(() {
                            _isLiked = !_isLiked;
                          });
                          
                          await _insightService.toggleInsightLike(widget.insight.id, user.uid, _isLiked);
                        },
                        padding: EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: _isSaved ? AppColors.gradientEnd : Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () async {
                      if (!_isSaved) {
                        NotificationService().playActionSound();
                      }
                      setState(() => _isSaved = !_isSaved);
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        if (_isSaved) {
                          await _insightService.saveInsight(user.uid, widget.insight);
                          if (mounted) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Insight saved', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                behavior: SnackBarBehavior.floating,
                                elevation: 0,
                                duration: const Duration(milliseconds: 1500),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        } else {
                          await _insightService.unsaveInsight(user.uid, widget.insight.id);
                        }
                      }
                    },
              ),
            ],
          ),
        ],
      ),
      StreamBuilder<List<InsightCommentModel>>(
            stream: countStream,
            builder: (context, snapshot) {
              final count = snapshot.hasData ? snapshot.data!.length : 0;
              return GestureDetector(
                onTap: _toggleComments,
                child: Container(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_up,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        size: 20,
                      ),
                      if (count > 0)
                        Text(
                          '$count comments',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFacebookStyleComment(
    InsightCommentModel comment,
    List<InsightCommentModel> allComments,
    int depth,
  ) {
    final replies = allComments
        .where((c) => c.replyToId == comment.id)
        .toList();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isLiked = comment.likedBy.contains(currentUserId);

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
                  margin: EdgeInsets.only(right: 8, top: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor, width: 2),
                      bottom: BorderSide(color: Theme.of(context).dividerColor, width: 2),
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
              BraidAvatar(
                identity: comment.authorUid,
                displayName: comment.authorName,
                imageUrl: comment.authorPhotoUrl,
                radius: 16,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ContactCacheService().getContactName(comment.authorUid, comment.authorName),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            comment.body,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 12, top: 4),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(
                            DateFormat(
                              'MMM d, h:mm a',
                            ).format(comment.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                            ),
                          ),
                          StreamBuilder<bool>(
                            stream: _insightService.hasCommentReaction(
                              widget.insight.id,
                              comment.id,
                            ),
                            initialData: isLiked,
                            builder: (context, reactionSnapshot) {
                              final reacted = reactionSnapshot.data ?? false;
                              return GestureDetector(
                                onTap: () {
                                  if (!reacted) {
                                    NotificationService().playActionSound();
                                  }
                                  _insightService.toggleCommentLike(
                                    widget.insight.id,
                                    comment.id,
                                    currentUserId,
                                    !reacted,
                                  );
                                },
                                child: Icon(
                                  reacted
                                      ? Icons.thumb_up
                                      : Icons.thumb_up_alt_outlined,
                                  size: 14,
                                  color: reacted
                                      ? AppColors.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() => _replyingTo = comment);
                              if (_commentsAnimController.isDismissed) {
                                _toggleComments();
                              }
                            },
                            child: Text(
                              'Reply',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                              ),
                            ),
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
          ...replies.map(
            (reply) =>
                _buildFacebookStyleComment(reply, allComments, depth + 1),
          ),
      ],
    );
  }

  Widget _buildCommentInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurfaceVariant!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyingTo != null)
            Padding(
              padding: EdgeInsets.only(bottom: 8.0, left: 4),
              child: Row(
                children: [
                  Text(
                    'Replying to ${ContactCacheService().getContactName(_replyingTo!.authorUid, _replyingTo!.authorName)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    ),
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
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Theme.of(context).cardColor,
                  ),
                ),
              ),
              SizedBox(width: 8),
                GestureDetector(
                  onTap: _submitDirectComment,
                  child: Icon(Icons.send, color: AppColors.gradientEnd),
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
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                    ),
                  ),
                  SizedBox(width: 8),
                  StreamBuilder<List<InsightCommentModel>>(
                    stream: countStream,
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.length
                          : 0;
                      return Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Expanded(
              child: StreamBuilder<List<InsightCommentModel>>(
                stream: _insightService.getComments(widget.insight.id),
                builder: (context, snapshot) {
                  final comments = snapshot.data ?? [];
                  if (comments.isEmpty) {
                    return Center(
                      child: Text(
                        'No comments yet.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                      ),
                    );
                  }

                  // Group comments by replyToId for nested rendering
                  final topLevelComments = comments
                      .where((c) => c.replyToId == null)
                      .toList();

                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    itemCount: topLevelComments.length,
                    itemBuilder: (context, index) {
                      return _buildFacebookStyleComment(
                        topLevelComments[index],
                        comments,
                        0,
                      );
                    },
                  );
                },
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
    final isMyInsight =
        widget.insight.authorUid == FirebaseAuth.instance.currentUser?.uid;

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
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: List.generate(widget.totalInsights, (idx) {
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 2),
                        height: 3,
                        decoration: BoxDecoration(
                          color: idx <= widget.insightIndex
                              ? AppColors.gradientEnd
                              : Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Author Info
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        BraidAvatar(
                          identity: widget.insight.authorUid,
                          displayName: widget.insight.authorName,
                          imageUrl: widget.insight.authorPhotoUrl,
                          radius: 20,
                        ),
                        if (isMyInsight)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CreateInsightScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: AppColors.gradientEnd,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.add,
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  size: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ContactCacheService().getContactName(widget.insight.authorUid, widget.insight.authorName),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                            ),
                          ),
                          Text(
                            DateFormat(
                              'MMM d, h:mm a',
                            ).format(widget.insight.createdAt),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        widget.ttsState == TtsState.playing
                            ? Icons.pause_circle_filled
                            : Icons.volume_up,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                      ),
                      onPressed: widget.onTogglePlay,
                    ),
                    if (!isMyInsight)
                      PopupMenuButton<String>(
                        tooltip: 'Reflection actions',
                        onSelected: (value) {
                          if (value == 'report') {
                            showReportDialog(
                              context,
                              targetType: 'insight',
                              targetId: widget.insight.id,
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'report',
                            child: Text('Report reflection'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Main Content Area
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final width = MediaQuery.of(context).size.width;
                    if (details.globalPosition.dx < width / 3) {
                      widget.onPrevious();
                    } else if (details.globalPosition.dx > width * 2 / 3) {
                      widget.onNext();
                    }
                  },
                  child: Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          bool shouldOpen = false;
                          if (notification is OverscrollNotification &&
                              notification.overscroll > 0) {
                            shouldOpen = true;
                          } else if (notification is ScrollUpdateNotification &&
                              notification.metrics.pixels >
                                  notification.metrics.maxScrollExtent + 30) {
                            shouldOpen = true;
                          }
                          if (shouldOpen &&
                              _commentsAnimController.isDismissed) {
                            _toggleComments();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 24,
                                  right: 24,
                                  top: 16,
                                  bottom: 100,
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: _buildInsightBody(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Floating Bottom Bar
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildFloatingBottomBar(),
                      ),
                    ],
                  ),
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
                ..translate(
                  0.0,
                  MediaQuery.of(context).size.height * -0.03 * value,
                )
                ..scale(_scaleAnimation.value)
                ..translate(
                  0.0,
                  MediaQuery.of(context).size.height * 0.03 * value,
                ),
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
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
            if (_commentsAnimController.isDismissed) {
              return SizedBox.shrink();
            }
            return GestureDetector(
              onTap: () {
                if (_commentsAnimController.isCompleted) {
                  _toggleComments();
                }
              },
              child: Container(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: _commentsAnimController.value * 0.5,
                ),
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




