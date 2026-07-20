import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bsgc_app/screens/main_hall_screen.dart';
import 'package:bsgc_app/screens/onboarding_screen.dart';
import 'package:bsgc_app/screens/inviter_selection_screen.dart';
import '../theme.dart';

class UserDataWrapper extends StatefulWidget {
  const UserDataWrapper({super.key});

  @override
  State<UserDataWrapper> createState() => _UserDataWrapperState();
}

class _UserDataWrapperState extends State<UserDataWrapper> {
  Widget? _resolvedScreen;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _resolvedScreen = Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.gradientEnd)));
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      Widget screen;

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final List<dynamic>? phoneNumbers = data?['phoneNumbers'];

        if (phoneNumbers == null || phoneNumbers.isEmpty) {
          screen = const OnboardingScreen();
        } else {
          final bool inviterSelectionComplete = data?['inviterSelectionComplete'] ?? false;
          if (!inviterSelectionComplete) {
            screen = const InviterSelectionScreen();
          } else {
            screen = const MainHallScreen();
          }
        }
      } else {
        screen = const OnboardingScreen();
      }

      if (mounted) {
        setState(() {
          _resolvedScreen = screen;
          _isLoading = false;
        });
      }
    } catch (e) {
      // On error, still go to MainHallScreen rather than showing error forever
      if (mounted) {
        setState(() {
          _resolvedScreen = const MainHallScreen();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _resolvedScreen == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.gradientEnd)),
      );
    }
    return _resolvedScreen!;
  }
}
