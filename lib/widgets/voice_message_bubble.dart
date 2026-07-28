import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

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
  static AudioPlayer? _activePlayer;
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  late Duration _duration;
  double _rate = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSeconds.clamp(1, 300));
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.onDurationChanged.listen((duration) {
      if (mounted && duration > Duration.zero) {
        setState(() => _duration = duration);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    if (_activePlayer == _player) _activePlayer = null;
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    try {
      if (_activePlayer != null && _activePlayer != _player) {
        await _activePlayer!.pause();
      }
      _activePlayer = _player;
      final uri = Uri.tryParse(widget.audioUrl);
      if (uri?.scheme == 'file') {
        final file = File.fromUri(uri!);
        if (!await file.exists()) {
          throw StateError('The local recording is no longer available.');
        }
        await _player.play(DeviceFileSource(file.path));
      } else if (uri?.scheme == 'https') {
        await _player.play(UrlSource(widget.audioUrl));
      } else {
        throw StateError('Unsupported recording source.');
      }
      await _player.setPlaybackRate(_rate);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Recording unavailable');
      }
    }
  }

  Future<void> _cycleRate() async {
    setState(() {
      _rate = switch (_rate) {
        1 => 1.25,
        1.25 => 1.5,
        1.5 => 2,
        _ => 1,
      };
    });
    await _player.setPlaybackRate(_rate);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
    if (_error != null) {
      return Semantics(
        label: _error,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded),
            SizedBox(width: 8),
            Text('Recording unavailable'),
          ],
        ),
      );
    }
    return Semantics(
      label:
          'Voice reflection, ${_format(_duration)}, '
          '${_state == PlayerState.playing ? 'playing' : 'paused'}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: _state == PlayerState.playing ? 'Pause' : 'Play',
              onPressed: _togglePlayback,
              icon: Icon(
                _state == PlayerState.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: progress,
                    onChanged: (value) {
                      final milliseconds =
                          (_duration.inMilliseconds * value).round();
                      unawaited(
                        _player.seek(Duration(milliseconds: milliseconds)),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_format(_position)} / ${_format(_duration)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _cycleRate,
              child: Text('${_rate}x'),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
