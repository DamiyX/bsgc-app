import 'package:flutter/foundation.dart';

/// Identifies one authenticated UI session.
///
/// The generation changes on every identity transition, including a
/// sign-out followed by signing back into the same account. This lets an
/// asynchronous result be tied to the session that started it instead of
/// relying on a UID comparison alone.
@immutable
class AccountSessionToken {
  const AccountSessionToken({required this.uid, required this.generation});

  final String? uid;
  final int generation;

  /// A private, in-memory key for replacing account-owned widget subtrees.
  /// The UID is deliberately not included so it cannot be surfaced by widget
  /// diagnostics or accidental logs.
  int get widgetKey => generation;
}

/// Tracks the active auth identity at the app/session boundary.
///
/// Firestore's persistent cache is shared by the Firebase app and cannot be
/// safely purged while listeners are active. This boundary therefore provides
/// the safe part we can enforce in-process: when auth changes, account-owned
/// widget trees receive a new key and stale asynchronous work can be rejected
/// by checking [isCurrent]. Device verification is still required for the
/// native Firestore cache itself; this class must not be treated as a cache
/// purge.
class AccountSessionBoundary {
  AccountSessionToken _current = const AccountSessionToken(
    uid: null,
    generation: 0,
  );

  AccountSessionToken get current => _current;

  /// Observes an auth identity and advances the generation on transitions.
  AccountSessionToken observe(String? uid) {
    if (_current.uid == uid) return _current;
    _current = AccountSessionToken(
      uid: uid,
      generation: _current.generation + 1,
    );
    return _current;
  }

  /// Returns true only when [token] belongs to the current identity epoch.
  bool isCurrent(AccountSessionToken token, {required String? uid}) {
    return token.generation == _current.generation && token.uid == uid;
  }
}
