import 'dart:async';
import 'dart:io';

import 'package:bsgc_app/services/voice_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('braid-voice-cache-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'first preparation reports progress and becomes an offline cache hit',
    () async {
      var downloadCount = 0;
      final progress = <VoiceCacheProgress>[];
      final service = VoiceCacheService(
        cacheRootProvider: (accountId) async =>
            Directory('${root.path}${Platform.pathSeparator}$accountId'),
        download: (uri) async {
          downloadCount++;
          return VoiceDownloadResponse(
            contentLength: 6,
            bytes: Stream.fromIterable([
              [1, 2],
              [3, 4],
              [5, 6],
            ]),
          );
        },
      );

      final first = await service.prepare(
        accountId: 'account-a',
        sourceUrl: 'https://media.example/reflection.m4a',
        onProgress: progress.add,
      );
      final cached = await service.prepare(
        accountId: 'account-a',
        sourceUrl: 'https://media.example/reflection.m4a',
      );

      expect(downloadCount, 1);
      expect(await first.file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(cached.wasCached, isTrue);
      expect(progress.last.fraction, 1);
    },
  );

  test('cache entries are private to the signed-in account', () async {
    var downloadCount = 0;
    final service = VoiceCacheService(
      cacheRootProvider: (accountId) async =>
          Directory('${root.path}${Platform.pathSeparator}$accountId'),
      download: (uri) async {
        downloadCount++;
        return VoiceDownloadResponse(
          contentLength: 1,
          bytes: Stream.value([7]),
        );
      },
    );

    await service.prepare(
      accountId: 'account-a',
      sourceUrl: 'https://media.example/private.m4a',
    );
    await service.prepare(
      accountId: 'account-b',
      sourceUrl: 'https://media.example/private.m4a',
    );

    expect(downloadCount, 2);
  });

  test('evicts expired entries and least-recently-used bytes', () async {
    var now = DateTime.utc(2026, 7, 29);
    final payloads = <String, List<int>>{
      '/one.m4a': [1, 1, 1, 1],
      '/two.m4a': [2, 2, 2, 2],
      '/three.m4a': [3, 3, 3, 3],
    };
    final service = VoiceCacheService(
      maxBytes: 8,
      expiry: const Duration(days: 2),
      now: () => now,
      cacheRootProvider: (accountId) async =>
          Directory('${root.path}${Platform.pathSeparator}$accountId'),
      download: (uri) async => VoiceDownloadResponse(
        contentLength: payloads[uri.path]!.length,
        bytes: Stream.value(payloads[uri.path]!),
      ),
    );

    await service.prepare(
      accountId: 'account-a',
      sourceUrl: 'https://media.example/one.m4a',
    );
    now = now.add(const Duration(hours: 1));
    final second = await service.prepare(
      accountId: 'account-a',
      sourceUrl: 'https://media.example/two.m4a',
    );
    now = now.add(const Duration(hours: 1));
    await service.prepare(
      accountId: 'account-a',
      sourceUrl: 'https://media.example/three.m4a',
    );

    expect(
      await service.lookup(
        accountId: 'account-a',
        sourceUrl: 'https://media.example/one.m4a',
      ),
      isNull,
    );
    expect(await second.file.exists(), isTrue);

    now = now.add(const Duration(days: 3));
    await service.prune('account-a');
    expect(await second.file.exists(), isFalse);
  });

  test('differentiates terminal and retryable download failures', () {
    expect(
      classifyVoiceCacheFailure(
        VoiceHttpException(statusCode: 401),
        hasCachedFile: false,
      ),
      VoiceCacheFailureKind.authorization,
    );
    expect(
      classifyVoiceCacheFailure(
        VoiceHttpException(statusCode: 404),
        hasCachedFile: false,
      ),
      VoiceCacheFailureKind.missing,
    );
    expect(
      classifyVoiceCacheFailure(
        const SocketException('offline'),
        hasCachedFile: false,
      ),
      VoiceCacheFailureKind.offlineMiss,
    );
    expect(
      classifyVoiceCacheFailure(
        VoiceHttpException(statusCode: 503),
        hasCachedFile: false,
      ),
      VoiceCacheFailureKind.transient,
    );
    expect(
      classifyVoiceCacheFailure(
        const FormatException('unsupported'),
        hasCachedFile: false,
      ),
      VoiceCacheFailureKind.unsupported,
    );
  });

  test('rejects unsupported sources before attempting download', () async {
    var downloaded = false;
    final service = VoiceCacheService(
      cacheRootProvider: (accountId) async => root,
      download: (uri) async {
        downloaded = true;
        return VoiceDownloadResponse(
          contentLength: 1,
          bytes: Stream.value([1]),
        );
      },
    );

    await expectLater(
      service.prepare(
        accountId: 'account-a',
        sourceUrl: 'http://media.example/reflection.exe',
      ),
      throwsA(
        isA<VoiceCacheException>().having(
          (error) => error.kind,
          'kind',
          VoiceCacheFailureKind.unsupported,
        ),
      ),
    );
    expect(downloaded, isFalse);
  });
}
