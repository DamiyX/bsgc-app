import 'dart:async';
import 'dart:io';

import 'package:bsgc_app/services/voice_cache_service.dart';
import 'package:bsgc_app/widgets/voice_message_bubble.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explicit download exposes progress then cached availability', (
    tester,
  ) async {
    final cache = _FakeVoiceCache(File('cached-voice.m4a'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceMessageBubble(
            audioUrl: 'https://media.example/voice.m4a',
            accountId: 'account-a',
            cacheRepository: cache,
            playbackController: _FakeVoicePlaybackController(),
            isMe: false,
            durationSeconds: 10,
            timestamp: DateTime(2026, 7, 29),
          ),
        ),
      ),
    );
    // A second frame resolves the asynchronous cache lookup.
    await tester.pump();

    expect(find.byTooltip('Download for offline use'), findsOneWidget);
    await tester.tap(find.byTooltip('Download for offline use'));
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);

    cache.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Available offline'), findsOneWidget);
  });

  test('failure messages distinguish user-relevant causes', () {
    expect(
      voiceCacheFailureMessage(VoiceCacheFailureKind.unsupported),
      contains('format'),
    );
    expect(
      voiceCacheFailureMessage(VoiceCacheFailureKind.authorization),
      contains('permission'),
    );
    expect(
      voiceCacheFailureMessage(VoiceCacheFailureKind.missing),
      contains('removed'),
    );
    expect(
      voiceCacheFailureMessage(VoiceCacheFailureKind.offlineMiss),
      contains('offline'),
    );
    expect(
      voiceCacheFailureMessage(VoiceCacheFailureKind.transient),
      contains('Try again'),
    );
  });
}

class _FakeVoicePlaybackController implements VoicePlaybackController {
  @override
  Stream<void> get onComplete => const Stream.empty();
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Future<void> dispose() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> playFile(String path) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setPlaybackRate(double rate) async {}
}

class _FakeVoiceCache implements VoiceCacheRepository {
  _FakeVoiceCache(this.file);

  final File file;
  Completer<VoiceCacheEntry>? _completer;

  @override
  Future<VoiceCacheEntry?> lookup({
    required String accountId,
    required String sourceUrl,
  }) async {
    return null;
  }

  @override
  Future<VoiceCacheEntry> prepare({
    required String accountId,
    required String sourceUrl,
    void Function(VoiceCacheProgress progress)? onProgress,
  }) {
    onProgress?.call(const VoiceCacheProgress(receivedBytes: 1, totalBytes: 2));
    _completer = Completer<VoiceCacheEntry>();
    return _completer!.future;
  }

  void complete() {
    _completer!.complete(
      VoiceCacheEntry(file: file, byteLength: 3, wasCached: false),
    );
  }
}
