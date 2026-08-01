import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/voice_cache_service.dart';

String voiceCacheFailureMessage(VoiceCacheFailureKind kind) {
  return switch (kind) {
    VoiceCacheFailureKind.unsupported =>
      'This recording format is not supported.',
    VoiceCacheFailureKind.authorization =>
      'You no longer have permission to access this recording.',
    VoiceCacheFailureKind.missing =>
      'This recording was removed or is no longer available.',
    VoiceCacheFailureKind.offlineMiss =>
      'Download this recording before listening offline.',
    VoiceCacheFailureKind.transient =>
      'The recording could not be prepared. Try again.',
  };
}

VoiceCacheFailureKind classifyVoicePlaybackFailure(Object error) {
  if (error is VoiceCacheException) return error.kind;
  final message = error.toString().toLowerCase();
  if (message.contains('unsupported') ||
      message.contains('codec') ||
      message.contains('format')) {
    return VoiceCacheFailureKind.unsupported;
  }
  if (message.contains('permission') ||
      message.contains('unauthorized') ||
      message.contains('forbidden')) {
    return VoiceCacheFailureKind.authorization;
  }
  if (message.contains('not found') ||
      message.contains('no longer available')) {
    return VoiceCacheFailureKind.missing;
  }
  return VoiceCacheFailureKind.transient;
}

enum VoiceBubbleCacheState { checking, availableOnline, downloading, cached }

abstract interface class VoicePlaybackController {
  Stream<PlayerState> get onStateChanged;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<void> get onComplete;

  Future<void> playFile(String path);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setPlaybackRate(double rate);
  Future<void> dispose();
}

class AudioplayersVoicePlaybackController implements VoicePlaybackController {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<PlayerState> get onStateChanged => _player.onPlayerStateChanged;
  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);
  @override
  Future<void> dispose() => _player.dispose();
}

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final String? accountId;
  final VoiceCacheRepository? cacheRepository;
  final VoicePlaybackController? playbackController;
  final bool isMe;
  final int durationSeconds;
  final DateTime timestamp;
  final bool isDraft;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    this.accountId,
    this.cacheRepository,
    this.playbackController,
    required this.isMe,
    required this.durationSeconds,
    required this.timestamp,
    this.isDraft = false,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  static VoicePlaybackController? _activePlayer;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final VoicePlaybackController _player;
  late final VoiceCacheRepository _cacheRepository;
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  late Duration _duration;
  double _rate = 1;
  VoiceBubbleCacheState _cacheState = VoiceBubbleCacheState.checking;
  VoiceCacheFailureKind? _failure;
  double? _downloadProgress;
  File? _cachedFile;

  String? get _accountId =>
      widget.accountId ?? FirebaseAuth.instance.currentUser?.uid;

  bool get _isRemoteSource => const {
    'https',
    'firebase-storage',
  }.contains(Uri.tryParse(widget.audioUrl)?.scheme.toLowerCase());

  @override
  void initState() {
    super.initState();
    _cacheRepository = widget.cacheRepository ?? VoiceCacheService.shared;
    _player =
        widget.playbackController ?? AudioplayersVoicePlaybackController();
    _duration = Duration(seconds: widget.durationSeconds.clamp(1, 300));
    _subscriptions.add(
      _player.onStateChanged.listen((state) {
        if (mounted) setState(() => _state = state);
      }),
    );
    _subscriptions.add(
      _player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      _player.onDurationChanged.listen((duration) {
        if (mounted && duration > Duration.zero) {
          setState(() => _duration = duration);
        }
      }),
    );
    _subscriptions.add(
      _player.onComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }),
    );
    unawaited(_refreshCacheAvailability());
  }

  Future<void> _refreshCacheAvailability() async {
    if (!_isRemoteSource) {
      if (mounted) {
        setState(() => _cacheState = VoiceBubbleCacheState.cached);
      }
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      if (mounted) {
        setState(() {
          _failure = VoiceCacheFailureKind.authorization;
          _cacheState = VoiceBubbleCacheState.availableOnline;
        });
      }
      return;
    }
    try {
      final cached = await _cacheRepository.lookup(
        accountId: accountId,
        sourceUrl: widget.audioUrl,
      );
      if (!mounted) return;
      setState(() {
        _cachedFile = cached?.file;
        _cacheState = cached == null
            ? VoiceBubbleCacheState.availableOnline
            : VoiceBubbleCacheState.cached;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = classifyVoicePlaybackFailure(error);
        _cacheState = VoiceBubbleCacheState.availableOnline;
      });
    }
  }

  @override
  void dispose() {
    if (_activePlayer == _player) _activePlayer = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_isRemoteSource && _cachedFile == null) {
      await _prepareCache(playAfterDownload: true);
      return;
    }
    await _playPreparedSource();
  }

  Future<void> _prepareCache({required bool playAfterDownload}) async {
    if (_cacheState == VoiceBubbleCacheState.downloading) return;
    final accountId = _accountId;
    if (accountId == null) {
      setState(() => _failure = VoiceCacheFailureKind.authorization);
      return;
    }
    setState(() {
      _failure = null;
      _downloadProgress = null;
      _cacheState = VoiceBubbleCacheState.downloading;
    });
    try {
      final entry = await _cacheRepository.prepare(
        accountId: accountId,
        sourceUrl: widget.audioUrl,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress.fraction);
        },
      );
      if (!mounted) return;
      setState(() {
        _cachedFile = entry.file;
        _cacheState = VoiceBubbleCacheState.cached;
        _downloadProgress = 1;
      });
      if (playAfterDownload) await _playPreparedSource();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = classifyVoicePlaybackFailure(error);
        _cacheState = VoiceBubbleCacheState.availableOnline;
      });
    }
  }

  Future<void> _playPreparedSource() async {
    try {
      if (_activePlayer != null && _activePlayer != _player) {
        await _activePlayer!.pause();
      }
      _activePlayer = _player;
      final cachedFile = _cachedFile;
      if (cachedFile != null) {
        if (!await cachedFile.exists()) {
          _cachedFile = null;
          _cacheState = VoiceBubbleCacheState.availableOnline;
          throw StateError('The recording is no longer available.');
        }
        await _player.playFile(cachedFile.path);
      } else {
        final uri = Uri.tryParse(widget.audioUrl);
        if (uri?.scheme != 'file') {
          throw const FormatException('Unsupported recording source.');
        }
        final file = File.fromUri(uri!);
        if (!await file.exists()) {
          throw StateError('The recording is no longer available.');
        }
        await _player.playFile(file.path);
      }
      await _player.setPlaybackRate(_rate);
      if (mounted) setState(() => _failure = null);
    } catch (error) {
      if (mounted) {
        setState(() => _failure = classifyVoicePlaybackFailure(error));
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
        : (_position.inMilliseconds / _duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final failure = _failure;
    return Semantics(
      label:
          'Voice reflection, ${_format(_duration)}, '
          '${_state == PlayerState.playing ? 'playing' : 'paused'}, '
          '${_cacheState == VoiceBubbleCacheState.cached ? 'available offline' : 'online'}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: _state == PlayerState.playing ? 'Pause' : 'Play',
                  onPressed: _cacheState == VoiceBubbleCacheState.downloading
                      ? null
                      : _togglePlayback,
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
                _buildCacheAction(),
                TextButton(onPressed: _cycleRate, child: Text('${_rate}x')),
              ],
            ),
            if (_cacheState == VoiceBubbleCacheState.downloading)
              Semantics(
                liveRegion: true,
                label: _downloadProgress == null
                    ? 'Downloading voice reflection'
                    : 'Downloading voice reflection, ${(_downloadProgress! * 100).round()} percent',
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    _downloadProgress == null
                        ? 'Downloading...'
                        : '${(_downloadProgress! * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            if (failure != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        voiceCacheFailureMessage(failure),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _isRemoteSource
                          ? () => _prepareCache(playAfterDownload: false)
                          : _togglePlayback,
                      child: Text(_isRemoteSource ? 'Download' : 'Retry'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheAction() {
    if (!_isRemoteSource) return const SizedBox.shrink();
    return switch (_cacheState) {
      VoiceBubbleCacheState.checking => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      VoiceBubbleCacheState.downloading => const SizedBox.shrink(),
      VoiceBubbleCacheState.cached => IconButton(
        tooltip: 'Available offline',
        onPressed: null,
        icon: const Icon(Icons.offline_pin_rounded),
      ),
      VoiceBubbleCacheState.availableOnline => IconButton(
        tooltip: 'Download for offline use',
        onPressed: () => _prepareCache(playAfterDownload: false),
        icon: const Icon(Icons.download_for_offline_outlined),
      ),
    };
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
