import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/current_profile_repository.dart';
import '../services/deep_link_service.dart';
import '../theme.dart';
import 'main_hall_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final suggestedName = FirebaseAuth.instance.currentUser?.displayName
        ?.trim();
    _displayNameController = TextEditingController(text: suggestedName ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Your sign-in expired. Please sign in again.');
      return;
    }

    setState(() => _isSaving = true);
    final displayName = _displayNameController.text.trim();
    final firestore = FirebaseFirestore.instance;
    final publicReference = firestore.collection('users_public').doc(user.uid);
    final privateReference = firestore
        .collection('users_private')
        .doc(user.uid);

    try {
      final existingProfiles = await Future.wait([
        publicReference.get(),
        privateReference.get(),
      ]);
      final batch = firestore.batch();
      batch.set(publicReference, {
        'schemaVersion': 2,
        'uid': user.uid,
        'displayName': displayName,
        if (user.photoURL?.isNotEmpty == true) 'photoUrl': user.photoURL,
        if (!existingProfiles[0].exists)
          'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(privateReference, {
        'schemaVersion': 2,
        'uid': user.uid,
        if (user.email?.isNotEmpty == true) 'email': user.email,
        'contactDiscoveryConsent': false,
        'onboardingComplete': true,
        if (!existingProfiles[1].exists)
          'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      CurrentProfileRepository.instance.invalidate(user.uid);
      if (user.displayName != displayName) {
        await user.updateDisplayName(displayName);
      }

      await _tryRedeemPendingInvite();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainHallScreen()),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      _showError(_friendlyFirebaseError(error));
    } catch (_) {
      _showError('We could not finish your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _tryRedeemPendingInvite() async {
    final deepLinks = DeepLinkService();
    final token = await deepLinks.getPendingInviteToken();
    if (token == null) return;

    try {
      await ChatService().redeemGroupInvite(token);
      await deepLinks.clearPendingInviteToken(token);
    } on ChatServiceException catch (error) {
      if (classifyInviteFailure(error.code) ==
          InviteFailureDisposition.terminal) {
        await deepLinks.clearPendingInviteToken(token);
      }
      // Retryable failures remain pending for Main Hall's retry/dismiss flow.
    } catch (_) {
      // Unknown failures remain pending for Main Hall's retry/dismiss flow.
    }
  }

  String _friendlyFirebaseError(FirebaseException error) {
    if (error.code == 'unavailable' || error.code == 'network-request-failed') {
      return 'You appear to be offline. Reconnect to finish setting up your profile.';
    }
    if (error.code == 'permission-denied') {
      return 'Your profile could not be saved securely. Please sign in again.';
    }
    return 'We could not finish your profile. Please try again.';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: 'Braid community profile',
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: AppColors.gradientEnd.withValues(
                          alpha: 0.12,
                        ),
                        child: Icon(
                          Icons.auto_stories_rounded,
                          size: 42,
                          color: AppColors.gradientEnd,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'How should your study group know you?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your name and profile photo are visible to people you '
                      'study with. Braid does not need access to your phone '
                      'contacts to connect you.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _displayNameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.name],
                      maxLength: 80,
                      enabled: !_isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        hintText: 'e.g. Godswill',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.length < 2) {
                          return 'Enter at least two characters.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) {
                        if (!_isSaving) _completeProfile();
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _completeProfile,
                        child: _isSaving
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Text('Continue to Braid'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'You can change your name and photo later in Profile.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
