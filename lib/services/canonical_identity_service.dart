import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalPublicIdentity {
  final String uid;
  final String displayName;
  final String? photoUrl;

  const CanonicalPublicIdentity({
    required this.uid,
    required this.displayName,
    this.photoUrl,
  });
}

abstract interface class CanonicalIdentitySource {
  Future<CanonicalPublicIdentity> load(String uid);
}

class FirestoreCanonicalIdentitySource implements CanonicalIdentitySource {
  final FirebaseFirestore _firestore;

  FirestoreCanonicalIdentitySource(this._firestore);

  static FirestoreCanonicalIdentitySource get defaultInstance =>
      FirestoreCanonicalIdentitySource(FirebaseFirestore.instance);

  @override
  Future<CanonicalPublicIdentity> load(String uid) async {
    final snapshot = await _firestore
        .collection('users_public')
        .doc(uid)
        .get(const GetOptions(source: Source.serverAndCache));
    final data = snapshot.data();
    final displayName = data?['displayName']?.toString().trim();
    if (!snapshot.exists || displayName == null || displayName.isEmpty) {
      throw StateError('Your public profile is unavailable. Try again.');
    }
    final rawPhotoUrl = data?['photoUrl']?.toString().trim();
    return CanonicalPublicIdentity(
      uid: uid,
      displayName: displayName,
      photoUrl: rawPhotoUrl == null || rawPhotoUrl.isEmpty ? null : rawPhotoUrl,
    );
  }
}
