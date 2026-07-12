import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../theme.dart';

class AddMemberSheet extends StatefulWidget {
  final String groupId;

  const AddMemberSheet({super.key, required this.groupId});

  @override
  _AddMemberSheetState createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  bool _isLoading = true;
  bool _isAdding = false;
  bool _permissionDenied = false;

  List<Map<String, dynamic>> _onPlatformContacts = [];
  List<Map<String, dynamic>> _offPlatformContacts = [];

  int get _selectedCount =>
      _onPlatformContacts.where((c) => c['selected'] == true).length;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

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
      List<Contact> contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      // Fetch all users from Firestore
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final allUsers = usersSnapshot.docs.map((d) => d.data()).toList();
      
      String cleanPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '');
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      Map<String, DateTime> activeCooldowns = {};
      if (currentUserId != null) {
        try {
          final cdSnap = await FirebaseFirestore.instance
              .collection('cooldowns')
              .where('users', arrayContains: currentUserId)
              .get();
          for (var doc in cdSnap.docs) {
            final data = doc.data();
            final users = List<String>.from(data['users'] ?? []);
            final otherUser = users.firstWhere((id) => id != currentUserId, orElse: () => '');
            final expiresAt = data['expiresAt'] as Timestamp?;
            if (otherUser.isNotEmpty && expiresAt != null) {
              final expirationDate = expiresAt.toDate();
              if (expirationDate.isAfter(DateTime.now())) {
                activeCooldowns[otherUser] = expirationDate;
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching cooldowns: $e');
        }
      }

      List<Map<String, dynamic>> onPlat = [];
      List<Map<String, dynamic>> offPlat = [];
      Set<String> addedUserIds = {};

      final userPhoneMap = <String, Map<String, dynamic>>{};
      for (var u in allUsers) {
        if (u['uid'] == currentUserId) continue;
        final uPhone = u['phone'] ?? '';
        final cleanUPhone = cleanPhone(uPhone);
        if (cleanUPhone.length >= 7) {
          for (int i = 7; i <= cleanUPhone.length && i <= 12; i++) {
            userPhoneMap[cleanUPhone.substring(cleanUPhone.length - i)] = u;
          }
        }
      }

      for (var contact in contacts) {
        if (contact.phones.isNotEmpty) {
          final String rawPhone = contact.phones.first.number;
          final String name = contact.displayName;
          final String cleanContactPhone = cleanPhone(rawPhone);

          bool matched = false;
          if (cleanContactPhone.length >= 7) {
            for (int i = cleanContactPhone.length > 12 ? 12 : cleanContactPhone.length; i >= 7; i--) {
              final testPhone = cleanContactPhone.substring(cleanContactPhone.length - i);
              if (userPhoneMap.containsKey(testPhone)) {
                final u = userPhoneMap[testPhone]!;
                if (!addedUserIds.contains(u['uid'])) {
                   onPlat.add({
                     'id': u['uid'],
                     'name': u['displayName'] != null && (u['displayName'] as String).isNotEmpty ? u['displayName'] : name,
                     'photo': u['photoURL'] != null && (u['photoURL'] as String).isNotEmpty ? u['photoURL'] : 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&q=80',
                     'selected': false,
                     'cooldownDate': activeCooldowns[u['uid']],
                   });
                   addedUserIds.add(u['uid']);
                }
                matched = true;
                break;
              }
            }
          }

          if (!matched) {
            offPlat.add({'name': name, 'phone': rawPhone});
          }
        }
      }

      onPlat.sort((a, b) {
        final DateTime? cdA = a['cooldownDate'];
        final DateTime? cdB = b['cooldownDate'];
        
        if (cdA == null && cdB == null) return (a['name'] as String).compareTo(b['name'] as String);
        if (cdA == null) return -1;
        if (cdB == null) return 1;
        
        // Both have cooldowns, sort by longest time left (cdB before cdA means cdB > cdA)
        return cdB.compareTo(cdA);
      });

      setState(() {
        _onPlatformContacts = onPlat;
        _offPlatformContacts = offPlat;
        _isLoading = false;
      });
    } else {
      setState(() {
        _permissionDenied = true;
        _isLoading = false;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Permission Needed'),
        content: const Text('We need contact access to find your friends. Please enable it in Settings.'),
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

  Future<void> _shareGeneric() async {
    await Share.share(
      'Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}',
    );
  }

  Future<void> _shareWhatsApp() async {
    final text = Uri.encodeComponent(
      'Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}',
    );
    final url = Uri.parse('whatsapp://send?text=$text');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('Could not launch');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not installed.')),
        );
      }
    }
  }

  Future<void> _shareEmail() async {
    final subject = Uri.encodeComponent('Join me on Braid!');
    final body = Uri.encodeComponent(
      'Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}',
    );
    final url = Uri.parse('mailto:?subject=$subject&body=$body');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('Could not launch');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email client configured.')),
        );
      }
    }
  }

  void _inviteOffPlatform(String phone) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Invite via',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
                title: const Text('WhatsApp'),
                onTap: () async {
                  Navigator.pop(context);
                  // Normalize phone number (replace leading 0 with +234, strip non-digits)
                  String cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
                  if (cleanPhone.startsWith('0')) {
                    cleanPhone = '+234${cleanPhone.substring(1)}';
                  }
                  final text = Uri.encodeComponent(
                    'Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}',
                  );
                  final url = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$text');
                  try {
                    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (!launched) throw Exception('Could not launch');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open WhatsApp.')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.sms, color: Colors.blue),
                title: const Text('SMS'),
                onTap: () async {
                  Navigator.pop(context);
                  final text = Uri.encodeComponent(
                    'Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}',
                  );
                  final url = Uri.parse('sms:$phone?body=$text');
                  try {
                    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (!launched) throw Exception('Could not launch');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open SMS app.')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Add Contacts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _permissionDenied
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Contact permissions denied.'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (_permissionDenied) {
                                  openAppSettings();
                                } else {
                                  _fetchContacts();
                                }
                              },
                              child: const Text('Open Settings'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_onPlatformContacts.isNotEmpty) ...[
                              _buildSectionHeader('On Braid'),
                              ..._onPlatformContacts.map(
                                (contact) => _buildOnPlatformTile(contact),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildSectionHeader('Other Contacts'),
                            ..._offPlatformContacts.map(
                              (contact) => _buildOffPlatformTile(contact),
                            ),
                            const SizedBox(
                              height: 100,
                            ), // padding for bottom bar
                          ],
                        ),
                      ),
              ),

              // Bottom Bar Area
              _buildBottomActionArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildOnPlatformTile(Map<String, dynamic> contact) {
    final DateTime? cd = contact['cooldownDate'];
    final bool hasCooldown = cd != null;
    int daysLeft = 0;
    double progress = 1.0;
    
    if (hasCooldown) {
      daysLeft = cd.difference(DateTime.now()).inDays;
      if (daysLeft < 0) daysLeft = 0;
      // 30 days remaining = 0% progress, 0 days remaining = 100% progress
      progress = (30 - daysLeft) / 30.0;
      if (progress < 0) progress = 0;
      if (progress > 1) progress = 1;
    }

    Widget avatarWidget = CircleAvatar(
      backgroundImage: NetworkImage(contact['photo']),
      radius: 24,
    );

    if (hasCooldown) {
      avatarWidget = Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
            ),
          ),
          CircleAvatar(
            backgroundImage: NetworkImage(contact['photo']),
            radius: 22, // Slightly smaller to fit inside ring
          ),
        ],
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: avatarWidget,
      title: Text(
        contact['name'],
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: hasCooldown ? Colors.grey : Colors.black,
        ),
      ),
      trailing: hasCooldown
          ? const Icon(Icons.lock_clock, color: Colors.grey)
          : Checkbox(
              value: contact['selected'],
              activeColor: AppColors.primary,
              onChanged: (val) {
                setState(() {
                  contact['selected'] = val;
                });
              },
            ),
      onTap: hasCooldown 
          ? () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cooldown Active'),
                  content: Text('You have $daysLeft more days cooldown before you can re-join or create a group chat with this friend.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          : () {
              setState(() {
                contact['selected'] = !contact['selected'];
              });
            },
    );
  }

  Widget _buildOffPlatformTile(Map<String, dynamic> contact) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        radius: 24,
        child: Text(
          contact['name'].isNotEmpty ? contact['name'][0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        contact['name'],
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(contact['phone']),
      trailing: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        onPressed: () {
          _inviteOffPlatform(contact['phone']);
        },
        child: const Text('Invite', style: TextStyle(color: Colors.black87)),
      ),
    );
  }

  Widget _buildBottomActionArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -4),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add to Group Button (Animated visibility)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _selectedCount > 0 ? 70 : 0,
              curve: Curves.easeInOut,
              child: _selectedCount > 0
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isAdding ? null : () async {
                            setState(() {
                              _isAdding = true;
                            });
                            try {
                              List<String> selectedIds = _onPlatformContacts
                                  .where((c) => c['selected'] == true)
                                  .map((c) => c['id'] as String)
                                  .toList();
                              
                              await ChatService().addMembersToGroup(widget.groupId, selectedIds);
                              
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Added $_selectedCount members to group',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to add members: $e')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isAdding = false;
                                });
                              }
                            }
                          },
                          child: _isAdding 
                            ? const SizedBox(
                                height: 20, 
                                width: 20, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              )
                            : Text(
                            'Add $_selectedCount to Group',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (_selectedCount > 0) const SizedBox(height: 16),

            const Divider(height: 1, color: Colors.black12),

            // Share Options Row (Spaced out evenly)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildShareIcon(
                    iconWidget: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Color(0xFF25D366),
                      size: 26,
                    ),
                    bgColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                    label: 'WhatsApp',
                    onTap: _shareWhatsApp,
                  ),
                  _buildShareIcon(
                    iconWidget: const Icon(
                      Icons.email_outlined,
                      color: Colors.blue,
                      size: 26,
                    ),
                    bgColor: Colors.blue.withValues(alpha: 0.1),
                    label: 'Email',
                    onTap: _shareEmail,
                  ),
                  _buildShareIcon(
                    iconWidget: Icon(
                      Icons.link,
                      color: Colors.grey[700]!,
                      size: 26,
                    ),
                    bgColor: Colors.grey[700]!.withValues(alpha: 0.1),
                    label: 'Copy Link',
                    onTap: () async {
                      await _shareGeneric();
                    },
                  ),
                  _buildShareIcon(
                    iconWidget: const Icon(
                      Icons.share,
                      color: Colors.black87,
                      size: 26,
                    ),
                    bgColor: Colors.black87.withValues(alpha: 0.1),
                    label: 'Share',
                    onTap: _shareGeneric,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareIcon({
    required Widget iconWidget,
    required Color bgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
