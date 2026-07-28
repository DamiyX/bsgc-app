import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/main_hall_screen.dart';
import '../screens/onboarding_screen.dart';
import '../theme.dart';

class UserDataWrapper extends StatefulWidget {
  const UserDataWrapper({super.key});

  @override
  State<UserDataWrapper> createState() => _UserDataWrapperState();
}

class _UserDataWrapperState extends State<UserDataWrapper> {
  Widget? _resolvedScreen;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setStateIfMounted(() {
        _resolvedScreen = const _SessionExpiredScreen();
        _loadError = null;
      });
      return;
    }

    setStateIfMounted(() {
      _resolvedScreen = null;
      _loadError = null;
    });

    try {
      final privateProfile = await _readPrivateProfile(user.uid);
      final onboardingComplete =
          privateProfile?['onboardingComplete'] == true;

      setStateIfMounted(() {
        _resolvedScreen = onboardingComplete
            ? const MainHallScreen()
            : const OnboardingScreen();
      });
    } catch (error) {
      setStateIfMounted(() => _loadError = error);
    }
  }

  Future<Map<String, dynamic>?> _readPrivateProfile(String uid) async {
    final reference = FirebaseFirestore.instance
        .collection('users_private')
        .doc(uid);

    try {
      final snapshot = await reference.get(
        const GetOptions(source: Source.serverAndCache),
      );
      return snapshot.data();
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable' &&
          error.code != 'network-request-failed') {
        rethrow;
      }
      final cachedSnapshot = await reference.get(
        const GetOptions(source: Source.cache),
      );
      if (cachedSnapshot.exists) return cachedSnapshot.data();
      rethrow;
    }
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return _ProfileLoadErrorScreen(onRetry: _loadUserData);
    }
    return _resolvedScreen ??
        const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.gradientEnd),
          ),
        );
  }
}

class _ProfileLoadErrorScreen extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ProfileLoadErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 52,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'We could not load your profile',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reconnect and try again. If this device has opened Braid '
                    'before, cached study data remains available once your '
                    'profile is verified.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionExpiredScreen extends StatelessWidget {
  const _SessionExpiredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Your session ended. Please sign in again.')),
    );
  }
}
