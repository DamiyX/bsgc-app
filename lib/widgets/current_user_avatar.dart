import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'braid_media.dart';

class CurrentUserAvatar extends StatelessWidget {
  const CurrentUserAvatar({
    super.key,
    required this.userId,
    required this.fallbackDisplayName,
    required this.fallbackPhotoUrl,
    required this.radius,
    this.useCanonicalProfile = true,
  });

  final String userId;
  final String fallbackDisplayName;
  final String? fallbackPhotoUrl;
  final double radius;
  final bool useCanonicalProfile;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty || !useCanonicalProfile) {
      return BraidAvatar(
        identity: 'me',
        displayName: fallbackDisplayName,
        imageUrl: fallbackPhotoUrl,
        radius: radius,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users_public')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final canonicalName = profile?['displayName']?.toString().trim();
        final canonicalPhoto = profile?['photoUrl']?.toString().trim();
        return BraidAvatar(
          identity: userId,
          displayName: canonicalName?.isNotEmpty == true
              ? canonicalName!
              : fallbackDisplayName,
          imageUrl: canonicalPhoto?.isNotEmpty == true
              ? canonicalPhoto
              : fallbackPhotoUrl,
          radius: radius,
        );
      },
    );
  }
}
