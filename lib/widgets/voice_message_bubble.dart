import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final int durationSeconds;
  final DateTime timestamp;
  final bool isDraft;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
    required this.durationSeconds,
    required this.timestamp,
    this.isDraft = false,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  static AudioPlayer? _currentlyPlayingPlayer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackRate = 1.0;

  void _togglePlaybackSpeed() {
    setState(() {
      if (_playbackRate == 1.0) {
        _playbackRate = 1.2;
      } else if (_playbackRate == 1.2) {
        _playbackRate = 1.5;
      } else if (_playbackRate == 1.5) {
        _playbackRate = 2.0;
      } else {
        _playbackRate = 1.0;
      }
      _audioPlayer.setPlaybackRate(_playbackRate);
    });
  }

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSeconds);
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });
  }

  @override
  void dispose() {
    if (_currentlyPlayingPlayer == _audioPlayer) {
      _currentlyPlayingPlayer = null;
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentlyPlayingPlayer != null && _currentlyPlayingPlayer != _audioPlayer) {
        await _currentlyPlayingPlayer!.pause();
      }
      _currentlyPlayingPlayer = _audioPlayer;

      if (widget.audioUrl.startsWith('http')) {
        await _audioPlayer.play(UrlSource(widget.audioUrl));
      } else {
        try {
          final Uint8List bytes = base64Decode(widget.audioUrl);
          await _audioPlayer.play(BytesSource(bytes));
        } catch (e) {
          debugPrint('Error decoding base64 audio: $e');
        }
      }
      _audioPlayer.setPlaybackRate(_playbackRate);
    }
  }

  Future<void> _exportAudio(String action) async {
    final TextEditingController nameController = TextEditingController(
      text: 'Voice_Note_${DateFormat('yyyyMMdd_HHmm').format(widget.timestamp)}'
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Text(action == 'download' ? 'Download Audio' : 'Share Audio', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter a name for this recording:', style: TextStyle(fontSize: 14)),
              SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: '.m4a',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, nameController.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: Text(action == 'download' ? 'Download' : 'Share'),
            ),
          ],
        );
      }
    );

    if (newName == null || newName.isEmpty) return;

    try {
      if (widget.audioUrl.startsWith('http')) {
        // In a real app we'd download the HTTP URL here. 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot export remote HTTP files yet.')));
        return;
      }

      final Uint8List bytes = base64Decode(widget.audioUrl);

      if (action == 'download') {
        final path = await FileSaver.instance.saveFile(
          name: newName,
          bytes: bytes,
          fileExtension: 'm4a',
          mimeType: MimeType.aac,
        );
        if (mounted && path.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to: $path')));
        }
      } else if (action == 'share') {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$newName.m4a';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(filePath)], text: 'Shared from Braid');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting audio: $e')));
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context).chatBubbleTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color fgColor = Theme.of(context).colorScheme.onSurface;
    if (widget.isMe && !widget.isDraft) {
      if (theme == ChatBubbleTheme.lightGray && !isDark) {
        fgColor = Colors.black87;
      } else {
        fgColor = Colors.white;
      }
    }
    final progress = _duration.inMilliseconds > 0 
        ? _position.inMilliseconds / _duration.inMilliseconds 
        : 0.0;

    return Container(
      width: MediaQuery.of(context).size.width * 0.65,
      padding: EdgeInsets.fromLTRB(4, 0, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: fgColor,
              size: 24,
            ),
            onPressed: _togglePlayPause,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: fgColor,
                    inactiveTrackColor: widget.isMe ? Colors.white24 : Theme.of(context).colorScheme.onSurface,
                    thumbColor: fgColor,
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      if (_duration.inMilliseconds > 0) {
                        final newPos = Duration(milliseconds: (value * _duration.inMilliseconds).toInt());
                        _audioPlayer.seek(newPos);
                      }
                    },
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPlaying ? _formatDuration(_position) : _formatDuration(_duration),
                      style: TextStyle(
                        color: widget.isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant, 
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm').format(widget.timestamp),
                      style: TextStyle(
                        color: widget.isMe ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant, 
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _togglePlaybackSpeed,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                '${_playbackRate}x',
                style: TextStyle(color: fgColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: fgColor, size: 20),
            onSelected: (value) {
              if (value == 'download') {
                _exportAudio('download');
              } else if (value == 'share') {
                _exportAudio('share');
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'download',
                  child: Text('Download'),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Text('Share'),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}
