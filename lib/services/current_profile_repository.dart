import 'canonical_identity_service.dart';

/// The public profile is the source of truth for identity shown inside Braid.
///
/// Firestore already provides the on-device cache used by the canonical source.
/// This small repository adds a process-local last-known value so a transient
/// read failure does not make an already known identity jump to Firebase Auth
/// or a generic placeholder. The cached value is always keyed by UID, so an
/// account change cannot leak the previous account's identity.
class CurrentProfileRepository {
  CurrentProfileRepository({CanonicalIdentitySource? source})
    : _source = source ?? FirestoreCanonicalIdentitySource.defaultInstance;

  static final CurrentProfileRepository instance = CurrentProfileRepository();

  final CanonicalIdentitySource _source;
  String? _cachedUid;
  CanonicalPublicIdentity? _cachedIdentity;
  String? _inFlightUid;
  Future<CanonicalPublicIdentity>? _inFlight;

  Future<CanonicalPublicIdentity> load(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw StateError('A signed-in account is required.');
    }

    if (_inFlightUid == normalizedUid && _inFlight != null) {
      return _inFlight!;
    }

    final request = _loadFromCanonicalSource(normalizedUid);
    _inFlightUid = normalizedUid;
    _inFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightUid = null;
      }
    }
  }

  Future<CanonicalPublicIdentity> _loadFromCanonicalSource(String uid) async {
    try {
      final identity = await _source.load(uid);
      if (identity.uid != uid) {
        throw StateError('The public profile returned the wrong account.');
      }
      _cachedUid = uid;
      _cachedIdentity = identity;
      return identity;
    } catch (_) {
      if (_cachedUid == uid && _cachedIdentity != null) {
        return _cachedIdentity!;
      }
      rethrow;
    }
  }

  /// Drops only the selected account. Call after a successful profile write so
  /// the next authored action re-reads the canonical Firestore value.
  void invalidate(String uid) {
    if (_cachedUid == uid.trim()) {
      _cachedUid = null;
      _cachedIdentity = null;
    }
  }

  /// Drops process-local identity state during sign-out/account replacement.
  void clear() {
    _cachedUid = null;
    _cachedIdentity = null;
  }
}
