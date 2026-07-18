import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:bsgc_app/services/storage_service.dart';
import 'dart:async';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../theme.dart';
import 'package:flutter/services.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final user = FirebaseAuth.instance.currentUser;

  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _emailController;

  final List<TextEditingController> _phoneControllers = [];
  final List<String> _completePhoneNumbers = [];

  String? _selectedGender;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _bioController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _bioController.text = data['bio'] ?? '';
            _selectedGender = data['gender'];

            // Load phone numbers
            List<dynamic> phones = data['phoneNumbers'] ?? [];
            if (phones.isEmpty && data['phone'] != null) {
              phones = [data['phone']]; // fallback for old data structure
            }

            if (phones.isEmpty) {
              // Add at least one empty field
              _phoneControllers.add(TextEditingController());
              _completePhoneNumbers.add('');
            } else {
              for (String phone in phones) {
                _phoneControllers.add(
                  TextEditingController(text: _getLocalPhoneNumber(phone)),
                );
                _completePhoneNumbers.add(phone);
              }
            }

            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Strips the country code from a stored phone number to get just the local digits.
  String _getLocalPhoneNumber(String phone) {
    if (phone.isEmpty) return '';
    if (phone.startsWith('+234')) return phone.substring(4);
    if (phone.startsWith('234')) return phone.substring(3);
    if (phone.startsWith('+')) {
      final withoutPlus = phone.substring(1);
      if (withoutPlus.length > 3) return withoutPlus.substring(3);
      return withoutPlus;
    }
    return phone;
  }

  void _addPhoneNumberField() {
    setState(() {
      _phoneControllers.add(TextEditingController());
      _completePhoneNumbers.add('');
    });
  }

  void _removePhoneNumberField(int index) {
    setState(() {
      _phoneControllers[index].dispose();
      _phoneControllers.removeAt(index);
      _completePhoneNumbers.removeAt(index);
    });
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isLoading = true);

      final bytes = await image.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1000,
        minHeight: 1000,
        quality: 85,
      );

      final url = await StorageService.uploadFile(compressed, folder: 'profiles');
      
      if (url.isEmpty) {
        throw Exception('Firebase Storage upload failed');
      }

      if (user != null) {
        await user!.updatePhotoURL(url);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .update({'photoURL': url});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated successfully!'),
            ),
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload timed out. It may finish in the background.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update picture: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      // Validate phone numbers (filter out empties, ensure at least one is valid)
      final validPhones = _completePhoneNumbers
          .where((p) => p.isNotEmpty)
          .toList();
      if (validPhones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter at least one valid phone number'),
          ),
        );
        return;
      }

      setState(() => _isLoading = true);
      try {
        if (user != null) {
          // Update Auth Profile
          try {
            await user!.updateDisplayName(_nameController.text.trim()).timeout(const Duration(seconds: 3));
          } catch (_) {}

          // Update Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .set({
                'displayName': _nameController.text.trim(),
                'bio': _bioController.text.trim(),
                'phoneNumbers': validPhones,
                'phone':
                    validPhones.first, // keep string for backward compatibility
                'gender': _selectedGender ?? 'Male',
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated successfully!')),
            );
            Navigator.pop(context, true);
          }
        }
      } on TimeoutException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile update queued offline.')),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update profile: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                            backgroundImage: user?.photoURL != null
                                ? NetworkImage(user!.photoURL!)
                                : null,
                            child: user?.photoURL == null
                                ? Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.gradientEnd,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 32),

                    Text(
                      'Full Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.gradientEnd, width: 2.0),
                        ),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                    SizedBox(height: 24),

                    Text(
                      'About Yourself',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _bioController,
                      maxLength: 150,
                      decoration: InputDecoration(
                        hintText: 'Share a brief bio...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.gradientEnd, width: 2.0),
                        ),
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                    ),
                    SizedBox(height: 12),

                    Text(
                      'Email Address',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      enabled: false,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(Icons.email_outlined),
                        fillColor: Theme.of(context).colorScheme.onSurfaceVariant,
                        filled: true,
                      ),
                    ),
                    SizedBox(height: 24),

                    Text(
                      'Phone Numbers',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    SizedBox(height: 8),

                    ...List.generate(_phoneControllers.length, (index) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: IntlPhoneField(
                                controller: _phoneControllers[index],
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppColors.gradientEnd, width: 2.0),
                                  ),
                                ),
                                initialCountryCode: 'NG',
                                onChanged: (phone) {
                                  _completePhoneNumbers[index] =
                                      phone.completeNumber;
                                },
                              ),
                            ),
                            if (_phoneControllers.length > 1)
                              IconButton(
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removePhoneNumberField(index),
                              ),
                          ],
                        ),
                      );
                    }),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addPhoneNumberField,
                        icon: Icon(Icons.add, color: AppColors.gradientEnd),
                        label: Text(
                          'Add another number',
                          style: TextStyle(color: AppColors.gradientEnd),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),

                    Text(
                      'Gender',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                    SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGender,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.gradientEnd, width: 2.0),
                        ),
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: ['Male', 'Female'].map((String val) {
                        return DropdownMenuItem(value: val, child: Text(val));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedGender = val);
                        }
                      },
                    ),
                    SizedBox(height: 48),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gradientEnd,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _saveProfile,
                        child: Text(
                          'Save Changes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    for (var c in _phoneControllers) {
      c.dispose();
    }
    super.dispose();
  }
}
