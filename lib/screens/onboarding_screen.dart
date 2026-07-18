import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import 'main_hall_screen.dart';
import 'inviter_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<String> _completePhoneNumbers = [''];
  final List<Key> _fieldKeys = [
    UniqueKey(),
  ]; // To force rebuilds when removing items
  bool _isLoading = false;

  void _addPhoneNumberField() {
    setState(() {
      _completePhoneNumbers.add('');
      _fieldKeys.add(UniqueKey());
    });
  }

  void _removePhoneNumberField(int index) {
    setState(() {
      _completePhoneNumbers.removeAt(index);
      _fieldKeys.removeAt(index);
    });
  }

  Future<void> _savePhoneAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

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
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Save to phoneNumbers array
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'phoneNumbers': FieldValue.arrayUnion(validPhones),
            'phone': validPhones.first, // keep string for backward compatibility
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Proceed offline
        }

        if (mounted) {
          // Check for Magic Link Inviter
          final prefs = await SharedPreferences.getInstance();
          final pendingInviterId = prefs.getString('pending_inviter_id');

          if (pendingInviterId != null && pendingInviterId.isNotEmpty) {
            // Apply the inviter automatically and mark selection as complete
            FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'referredBy': pendingInviterId,
                  'inviterSelectionComplete': true,
                }, SetOptions(merge: true));

            // Remove it so it doesn't trigger again
            await prefs.remove('pending_inviter_id');
            
            // Navigate straight to Main Hall since they already have an inviter
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainHallScreen()),
            );
          } else {
            // No inviter yet, take them to the Inviter Selection Screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const InviterSelectionScreen()),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving phone number: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Complete Profile',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      SizedBox(height: 16),
                      Icon(
                        Icons.connect_without_contact,
                        size: 80,
                        color: AppColors.gradientEnd,
                      ),
                      SizedBox(height: 32),
                      Text(
                        'Let friends find you',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Enter your phone numbers so friends can easily invite you to study groups.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      SizedBox(height: 48),

                      ...List.generate(_completePhoneNumbers.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: IntlPhoneField(
                                  key: _fieldKeys[index],
                                  decoration: InputDecoration(
                                    labelText: 'Phone Number ${index + 1}',
                                    floatingLabelStyle: TextStyle(color: AppColors.gradientStart),
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.gradientStart,
                                        width: 2.0,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  initialCountryCode: 'NG',
                                  onChanged: (phone) {
                                    _completePhoneNumbers[index] =
                                        phone.completeNumber;
                                  },
                                ),
                              ),
                              if (_completePhoneNumbers.length > 1)
                                IconButton(
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _removePhoneNumberField(index),
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
                    ],
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _savePhoneAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gradientEnd,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
