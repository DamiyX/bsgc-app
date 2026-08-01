import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';
import '../services/firestore_commit_service.dart';
import '../widgets/current_user_avatar.dart';

const profilePicturePendingMessage =
    'The profile picture change is queued locally. Reconnect and retry to finish saving.';
const profileChangesPendingMessage =
    'Your profile changes are queued locally. Reconnect and retry to finish saving.';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _user = FirebaseAuth.instance.currentUser;
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _user?.displayName ?? '');
    _bioController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users_public')
          .doc(user.uid)
          .get();
      final data = snapshot.data();
      if (data != null) {
        _nameController.text =
            data['displayName']?.toString() ?? _nameController.text;
        _bioController.text = data['bio']?.toString() ?? '';
      }
    } catch (_) {
      // Firestore serves cached data when available; the form remains usable
      // with the authenticated profile if no cached public document exists.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final user = _user;
    if (user == null || _isLoading) return;

    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _isLoading = true);

    try {
      final compressed = await FlutterImageCompress.compressWithList(
        await image.readAsBytes(),
        minWidth: 1000,
        minHeight: 1000,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      final storagePath = await StorageService.uploadProfileImage(
        bytes: compressed,
        userId: user.uid,
      );
      final reference = FirebaseFirestore.instance
          .collection('users_public')
          .doc(user.uid);
      await reference.update({
        'photoUrl': storagePath,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await waitForDocumentCommit(reference);
      _showMessage('Profile picture updated.');
    } on TimeoutException {
      _showMessage(profilePicturePendingMessage);
    } on FirebaseException catch (error) {
      _showMessage(_friendlyError(error));
    } catch (_) {
      _showMessage('The picture could not be uploaded. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _user;
    if (user == null) return;

    setState(() => _isLoading = true);
    final displayName = _nameController.text.trim();
    try {
      final reference = FirebaseFirestore.instance
          .collection('users_public')
          .doc(user.uid);
      await reference.update({
        'displayName': displayName,
        'bio': _bioController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await waitForDocumentCommit(reference);
      if (user.displayName != displayName) {
        try {
          await user.updateDisplayName(displayName);
        } catch (_) {
          // Firestore remains the canonical in-app profile source.
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TimeoutException {
      _showMessage(profileChangesPendingMessage);
    } on FirebaseException catch (error) {
      _showMessage(_friendlyError(error));
    } catch (_) {
      _showMessage('Your profile could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(FirebaseException error) {
    if (error.code == 'unavailable' || error.code == 'network-request-failed') {
      return 'You appear to be offline. Reconnect and try again.';
    }
    if (error.code == 'permission-denied') {
      return 'Your profile could not be updated securely.';
    }
    return 'Your profile could not be updated. Please try again.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Stack(
                              children: [
                                CurrentUserAvatar(
                                  userId: user?.uid ?? '',
                                  fallbackDisplayName:
                                      user?.displayName ?? 'You',
                                  fallbackPhotoUrl: user?.photoURL,
                                  radius: 52,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Semantics(
                                    button: true,
                                    label: 'Change profile picture',
                                    child: IconButton.filled(
                                      onPressed: _pickImage,
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            maxLength: 80,
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if ((value?.trim().length ?? 0) < 2) {
                                return 'Enter at least two characters.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _bioController,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'About you',
                              hintText:
                                  'A short introduction for your study groups',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Braid does not publish your email or request your '
                            'phone contacts.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed: _saveProfile,
                              child: const Text('Save changes'),
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

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }
}
