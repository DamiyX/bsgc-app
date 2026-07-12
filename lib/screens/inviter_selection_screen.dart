import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';
import 'main_hall_screen.dart';

class InviterSelectionScreen extends StatefulWidget {
  const InviterSelectionScreen({super.key});

  @override
  State<InviterSelectionScreen> createState() => _InviterSelectionScreenState();
}

class _InviterSelectionScreenState extends State<InviterSelectionScreen> {
  bool _isLoading = false;
  bool _permissionDenied = false;
  List<Map<String, dynamic>> _matchedFriends = [];

  @override
  void initState() {
    super.initState();
    _requestContactsAndFindFriends();
  }

  Future<void> _requestContactsAndFindFriends() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      final status = await Permission.contacts.request();
      
      if (status.isPermanentlyDenied) {
        setState(() {
          _permissionDenied = true;
          _isLoading = false;
        });
        if (mounted) _showPermissionDialog();
        return;
      }

      if (status.isGranted) {
        // Fetch contacts without photos for much faster performance
        final contacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
        
        // Extract all normalized phone numbers from contacts
        final Set<String> contactPhoneNumbers = {};
        for (final contact in contacts) {
          for (final phone in contact.phones) {
            final normalized = phone.normalizedNumber.replaceAll(RegExp(r'\D'), '');
            if (normalized.length >= 10) {
              contactPhoneNumbers.add(normalized.substring(normalized.length - 10));
            } else if (normalized.isNotEmpty) {
              contactPhoneNumbers.add(normalized);
            }
          }
        }

        // Query Firestore for users with these phone numbers
        if (contactPhoneNumbers.isNotEmpty) {
          final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
          
          final List<Map<String, dynamic>> matches = [];
          final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

          for (final doc in usersSnapshot.docs) {
            if (doc.id == currentUserUid) continue; // Skip self
            
            final data = doc.data();
            final List<dynamic> userPhones = data['phoneNumbers'] ?? [];
            
            bool isMatch = false;
            for (final up in userPhones) {
              final normalizedUp = up.toString().replaceAll(RegExp(r'\D'), '');
              String lookup = normalizedUp;
              if (normalizedUp.length >= 10) {
                lookup = normalizedUp.substring(normalizedUp.length - 10);
              }
              if (contactPhoneNumbers.contains(lookup)) {
                isMatch = true;
                break;
              }
            }

            if (isMatch) {
              matches.add({
                'uid': doc.id,
                'displayName': data['displayName'] ?? 'Believer',
                'photoURL': data['photoURL'] ?? '',
              });
            }
          }

          if (mounted) {
            setState(() {
              _matchedFriends = matches;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error finding friends: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Permission Needed'),
        content: const Text('We need contact access to find who invited you. Please enable it in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectInviter(String inviterUid, String inviterName) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'referredBy': inviterUid,
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() => _isLoading = false);
          _showWelcomeDialog(inviterName);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showWelcomeDialog(String inviterName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.all(32),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/icon2.png', height: 80)),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Braid.',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'You\'re now part of $inviterName\'s network—a community of believers growing and studying together in faith.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              const Text(
                '"As iron sharpens iron, so one person sharpens another."\n— Proverbs 27:17',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _navigateToMain();
                  },
                  child: const Text('Enter Braid'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Future<void> _navigateToMain() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'inviterSelectionComplete': true,
      }, SetOptions(merge: true));
    }
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainHallScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Find Friends', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _navigateToMain,
            child: const Text('Skip', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.gradientEnd),
                  SizedBox(height: 16),
                  Text('Scanning for friends on Braid...'),
                ],
              ),
            )
          : _permissionDenied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.contacts_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'We need contact access to find who invited you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            if (_permissionDenied) {
                              openAppSettings();
                            } else {
                              _requestContactsAndFindFriends();
                            }
                          },
                          child: Text(_permissionDenied ? 'Open Settings' : 'Allow Access'),
                        )
                      ],
                    ),
                  ),
                )
              : _matchedFriends.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.group_off_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No friends found on Braid yet.',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _navigateToMain,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gradientStart,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Continue to App'),
                          )
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text(
                            'Who invited you to Braid?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _matchedFriends.length,
                            itemBuilder: (context, index) {
                              final friend = _matchedFriends[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: friend['photoURL'] != ''
                                      ? NetworkImage(friend['photoURL'])
                                      : null,
                                  child: friend['photoURL'] == ''
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                title: Text(friend['displayName']),
                                subtitle: const Text('Tap to select'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _selectInviter(friend['uid'], friend['displayName']),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}


