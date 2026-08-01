import 'dart:async';

import 'package:bsgc_app/services/canonical_identity_service.dart';
import 'package:bsgc_app/services/current_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'canonical profile replaces stale Auth identity and is cached by UID',
    () async {
      final source = _FakeIdentitySource({
        'alice': const CanonicalPublicIdentity(
          uid: 'alice',
          displayName: 'Canonical Alice',
          photoUrl: 'users/alice/profile/avatar.jpg',
        ),
      });
      final repository = CurrentProfileRepository(source: source);

      final first = await repository.load(' alice ');
      expect(first.displayName, 'Canonical Alice');
      expect(first.photoUrl, 'users/alice/profile/avatar.jpg');
      expect(source.loadCount, 1);

      source.fail = true;
      final cached = await repository.load('alice');
      expect(cached.displayName, 'Canonical Alice');
      expect(source.loadCount, 2);
    },
  );

  test('cached identity never crosses an account boundary', () async {
    final source = _FakeIdentitySource({
      'alice': const CanonicalPublicIdentity(
        uid: 'alice',
        displayName: 'Alice',
      ),
    });
    final repository = CurrentProfileRepository(source: source);

    await repository.load('alice');
    source.fail = true;

    await expectLater(repository.load('bob'), throwsA(isA<StateError>()));
  });

  test('concurrent loads for one account share one source request', () async {
    final source = _FakeIdentitySource({
      'alice': const CanonicalPublicIdentity(
        uid: 'alice',
        displayName: 'Alice',
      ),
    })..pause = true;
    final repository = CurrentProfileRepository(source: source);

    final first = repository.load('alice');
    final second = repository.load('alice');
    expect(source.loadCount, 1);
    source.complete();

    expect((await Future.wait([first, second])).map((item) => item.uid), [
      'alice',
      'alice',
    ]);
  });

  test('source cannot return an identity for a different UID', () async {
    final source = _FakeIdentitySource({
      'alice': const CanonicalPublicIdentity(
        uid: 'someone-else',
        displayName: 'Imposter',
      ),
    });
    final repository = CurrentProfileRepository(source: source);

    await expectLater(repository.load('alice'), throwsA(isA<StateError>()));
  });
}

class _FakeIdentitySource implements CanonicalIdentitySource {
  _FakeIdentitySource(this.identities);

  final Map<String, CanonicalPublicIdentity> identities;
  int loadCount = 0;
  bool fail = false;
  bool pause = false;
  Completer<CanonicalPublicIdentity>? _pending;

  @override
  Future<CanonicalPublicIdentity> load(String uid) {
    loadCount++;
    if (fail) return Future.error(StateError('offline'));
    final identity = identities[uid];
    if (identity == null) return Future.error(StateError('missing'));
    if (!pause) return Future.value(identity);
    final pending = Completer<CanonicalPublicIdentity>();
    _pending = pending;
    return pending.future.then((_) => identity);
  }

  void complete() {
    _pending?.complete(identities.values.first);
  }
}
