import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'deep_link_service.dart';
import 'draft_service.dart';
import 'message_outbox_service.dart';
import 'voice_cache_service.dart';
import 'current_profile_repository.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get userStream => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuthentication = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuthentication.accessToken,
        idToken: googleAuthentication.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) await _ensureVersionedProfile(user);
      return userCredential;
    } catch (error) {
      if (kDebugMode) debugPrint('Google sign-in failed: $error');
      rethrow;
    }
  }

  Future<void> _ensureVersionedProfile(User user) async {
    final firestore = FirebaseFirestore.instance;
    final publicReference = firestore.collection('users_public').doc(user.uid);
    final privateReference = firestore
        .collection('users_private')
        .doc(user.uid);
    final existing = await Future.wait([
      publicReference.get(),
      privateReference.get(),
    ]);
    final batch = firestore.batch();

    if (!existing[0].exists) {
      final displayName = user.displayName?.trim();
      batch.set(publicReference, {
        'schemaVersion': 2,
        'uid': user.uid,
        'displayName': displayName?.isNotEmpty == true
            ? displayName
            : 'Believer',
        if (user.photoURL?.isNotEmpty == true) 'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (!existing[1].exists) {
      batch.set(privateReference, {
        'schemaVersion': 2,
        'uid': user.uid,
        if (user.email?.isNotEmpty == true) 'email': user.email,
        'contactDiscoveryConsent': false,
        'connectionCount': 0,
        'onboardingComplete': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Kept as a compatibility hook; sensitive engagement counters are no
  /// longer stored inside the user profile.
  Future<void> recordInteraction() async {}

  Future<void> signOut() async {
    final signingOutUid = _auth.currentUser?.uid;
    try {
      await NotificationService().unregisterCurrentDevice();
    } catch (error) {
      if (kDebugMode) debugPrint('Device-token cleanup failed: $error');
    }
    try {
      await NotificationService().destination.discardAll();
    } catch (error) {
      if (kDebugMode) debugPrint('Notification-route cleanup failed: $error');
    }
    try {
      final inviteToken = await DeepLinkService().getPendingInviteToken();
      if (inviteToken != null) {
        await DeepLinkService().clearPendingInviteToken(inviteToken);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('Invite-route cleanup failed: $error');
    }

    try {
      await _googleSignIn.signOut();
    } catch (error) {
      if (kDebugMode) debugPrint('Google sign-out failed: $error');
    } finally {
      await _auth.signOut();
      CurrentProfileRepository.instance.clear();
      if (signingOutUid != null) {
        final cleanupOperations =
            <({String name, Future<void> Function() run})>[
              (
                name: 'draft',
                run: () => DraftService().clearAllForUser(signingOutUid),
              ),
              (
                name: 'outbox',
                run: () =>
                    MessageOutboxService().clearAllForUser(signingOutUid),
              ),
              (
                name: 'voice cache',
                run: () =>
                    VoiceCacheService.shared.clearAllForUser(signingOutUid),
              ),
            ];
        for (final cleanup in cleanupOperations) {
          try {
            await cleanup.run();
          } catch (error) {
            if (kDebugMode) {
              debugPrint('${cleanup.name} cleanup failed: $error');
            }
          }
        }
      }
      try {
        final preferences = await SharedPreferences.getInstance();
        await Future.wait([
          preferences.remove('active_group_id'),
          preferences.remove('active_route_timestamp'),
        ]);
      } catch (error) {
        if (kDebugMode) debugPrint('Navigation-state cleanup failed: $error');
      }
      try {
        await DefaultCacheManager().emptyCache();
      } catch (error) {
        if (kDebugMode) debugPrint('Image-cache cleanup failed: $error');
      }
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    }
  }
}
