import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bsgc_app/screens/main_hall_screen.dart';
import 'package:bsgc_app/screens/onboarding_screen.dart';
import 'package:bsgc_app/screens/inviter_selection_screen.dart';

class UserDataWrapper extends StatelessWidget {
  const UserDataWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Error loading profile: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic>? phoneNumbers = data?['phoneNumbers'];

          if (phoneNumbers == null || phoneNumbers.isEmpty) {
            return const OnboardingScreen();
          }

          final bool inviterSelectionComplete = data?['inviterSelectionComplete'] ?? false;
          if (!inviterSelectionComplete) {
            return const InviterSelectionScreen();
          }
        } else {
          // If the user document doesn't exist yet, show onboarding
          return const OnboardingScreen();
        }

        // If phone number exists, proceed to the main app
        return const MainHallScreen();
      },
    );
  }
}
