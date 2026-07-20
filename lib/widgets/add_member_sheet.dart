import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isRefreshing = false;
  bool _permissionDenied = false;
  String _searchQuery = '';

  List<Map<String, dynamic>> _onPlatformContacts = [];
  List<Map<String, dynamic>> _offPlatformContacts = [];
  
  String? _currentDragLetter;
  bool _isScrollingList = false;
  Timer? _hideLetterTimer;
  double _scrollThumbY = 0.0;

  int get _selectedCount =>
      _onPlatformContacts.where((c) => c['selected'] == true).length;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _fetchContacts();
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedOnPlat = prefs.getString('cached_on_plat_contacts');
      final cachedOffPlat = prefs.getString('cached_off_plat_contacts');
      
      if (cachedOnPlat != null && cachedOffPlat != null) {
        if (mounted) {
          setState(() {
            final decodedOnPlat = List<Map<String, dynamic>>.from(jsonDecode(cachedOnPlat));
            for (var c in decodedOnPlat) {
              if (c['cooldownDate'] != null) {
                c['cooldownDate'] = DateTime.parse(c['cooldownDate']);
              }
            }
            _onPlatformContacts = decodedOnPlat;
            _offPlatformContacts = List<Map<String, dynamic>>.from(jsonDecode(cachedOffPlat));
            _isLoading = false; // Stop loading instantly!
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  Future<void> _fetchContacts() async {
    // Brief delay to let bottom sheet animation start smoothly
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;

    if (_onPlatformContacts.isEmpty && _offPlatformContacts.isEmpty) {
      setState(() {
        _isLoading = true;
        _permissionDenied = false;
      });
    } else {
      // Cache is visible — show subtle sync indicator instead of blocking spinner
      setState(() {
        _isRefreshing = true;
        _permissionDenied = false;
      });
    }

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

      List<Map<String, String>> simpleContacts = [];
      for (var c in contacts) {
        if (c.phones.isNotEmpty) {
          simpleContacts.add({
            'name': c.displayName,
            'phone': c.phones.first.number,
          });
        }
      }

      final result = await compute(_processContactsIsolate, {
        'contacts': simpleContacts,
        'users': allUsers,
        'currentUserId': currentUserId ?? '',
        'cooldowns': activeCooldowns,
      });

      setState(() {
        _onPlatformContacts = result['onPlat'];
        _offPlatformContacts = result['offPlat'];
        _isLoading = false;
        _isRefreshing = false;
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        final encodedOnPlat = _onPlatformContacts.map((c) {
          final newMap = Map<String, dynamic>.from(c);
          if (newMap['cooldownDate'] is DateTime) {
            newMap['cooldownDate'] = (newMap['cooldownDate'] as DateTime).toIso8601String();
          }
          return newMap;
        }).toList();
        await prefs.setString('cached_on_plat_contacts', jsonEncode(encodedOnPlat));
        await prefs.setString('cached_off_plat_contacts', jsonEncode(_offPlatformContacts));
      } catch (e) {
        debugPrint('Error saving to cache: $e');
      }
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
        title: Text('Contact Permission Needed'),
        content: Text('We need contact access to find your friends. Please enable it in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('Open Settings'),
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
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Invite via',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
                title: Text('WhatsApp'),
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
                leading: Icon(Icons.sms, color: Colors.blue),
                title: Text('SMS'),
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
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

              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.light ? Colors.grey[200] : Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                ),
              ),

              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gradientEnd))
                    : _permissionDenied
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Contact permissions denied.'),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (_permissionDenied) {
                                  openAppSettings();
                                } else {
                                  _fetchContacts();
                                }
                              },
                              child: Text('Open Settings'),
                            ),
                          ],
                        ),
                      )
                    : _buildVirtualizedContactList(scrollController),
              ),

              // Bottom Bar Area
              _buildBottomActionArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVirtualizedContactList(ScrollController scrollController) {
    final filteredOnPlat = _searchQuery.isEmpty
        ? _onPlatformContacts
        : _onPlatformContacts.where((c) => (c['name'] as String).toLowerCase().contains(_searchQuery)).toList();
    final filteredOffPlat = _searchQuery.isEmpty
        ? _offPlatformContacts
        : _offPlatformContacts.where((c) => (c['name'] as String).toLowerCase().contains(_searchQuery)).toList();

    // Build a flat list of items: [onPlatHeader?, ...onPlatItems, spacer?, offPlatHeader, ...offPlatItems, bottomSpacer]
    final List<_ContactListItem> items = [];

    if (filteredOnPlat.isNotEmpty) {
      items.add(_ContactListItem(type: _ItemType.header, headerTitle: 'On Braid'));
      for (var c in filteredOnPlat) {
        items.add(_ContactListItem(type: _ItemType.onPlatform, contact: c));
      }
      items.add(_ContactListItem(type: _ItemType.spacer));
    }

    items.add(_ContactListItem(type: _ItemType.header, headerTitle: 'Other Contacts'));
    for (var c in filteredOffPlat) {
      items.add(_ContactListItem(type: _ItemType.offPlatform, contact: c));
    }
    items.add(_ContactListItem(type: _ItemType.spacer)); // Bottom padding

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollUpdateNotification) {
              final offset = notification.metrics.pixels;
              final maxExtent = notification.metrics.maxScrollExtent;
              final viewport = notification.metrics.viewportDimension;

              // Estimate which letter is visible based on scroll offset
              String? newLetter;
              final estimatedIndex = (offset / 64.0).clamp(0, items.length - 1).toInt();
              if (estimatedIndex >= 0 && estimatedIndex < items.length) {
                final item = items[estimatedIndex];
                if (item.contact != null) {
                  final name = item.contact!['name'] as String;
                  if (name.isNotEmpty) newLetter = name[0].toUpperCase();
                }
              }

              // Single consolidated setState instead of 3 separate ones
              bool needsUpdate = false;
              if (newLetter != null && newLetter != _currentDragLetter) {
                _currentDragLetter = newLetter;
                needsUpdate = true;
              }
              if (!_isScrollingList) {
                _isScrollingList = true;
                needsUpdate = true;
              }
              if (maxExtent > 0) {
                final newThumbY = (offset / maxExtent) * (viewport - 60);
                if ((newThumbY - _scrollThumbY).abs() > 2.0) {
                  _scrollThumbY = newThumbY;
                  needsUpdate = true;
                }
              }

              if (needsUpdate) setState(() {});

              _hideLetterTimer?.cancel();
              _hideLetterTimer = Timer(const Duration(milliseconds: 800), () {
                if (mounted) setState(() => _isScrollingList = false);
              });
            }
            return false;
          },
          child: Scrollbar(
            controller: scrollController,
            child: ListView.builder(
              controller: scrollController,
              itemCount: items.length,
              // Use estimated height for smooth scrollbar
              itemExtentBuilder: (index, _) {
                final item = items[index];
                if (item.type == _ItemType.header) return 44.0;
                if (item.type == _ItemType.spacer) return 16.0;
                return 64.0; // ListTile height
              },
              itemBuilder: (context, index) {
                final item = items[index];
                switch (item.type) {
                  case _ItemType.header:
                    return _buildSectionHeader(item.headerTitle!);
                  case _ItemType.spacer:
                    return const SizedBox(height: 16);
                  case _ItemType.onPlatform:
                    return _buildOnPlatformTile(item.contact!);
                  case _ItemType.offPlatform:
                    return _buildOffPlatformTile(item.contact!);
                }
              },
            ),
          ),
        ),
        if (_isRefreshing)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gradientEnd)),
                    SizedBox(width: 8),
                    Text('Syncing...', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        if (_isScrollingList && _currentDragLetter != null && _searchQuery.isEmpty)
          Positioned(
            right: 16,
            top: _scrollThumbY.clamp(0.0, MediaQuery.of(context).size.height),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.gradientEnd,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Theme.of(context).dividerColor, blurRadius: 8, offset: Offset(0, 2))],
              ),
              alignment: Alignment.center,
              child: Text(
                _currentDragLetter!,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAlphabetSidebar(ScrollController controller) {
    return SizedBox.shrink(); // Disabled in favor of popup scroll indicator
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      backgroundImage: CachedNetworkImageProvider(contact['photo']),
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
              backgroundColor: Theme.of(context).dividerColor,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
            ),
          ),
          CircleAvatar(
            backgroundImage: CachedNetworkImageProvider(contact['photo']),
            radius: 22, // Slightly smaller to fit inside ring
          ),
        ],
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: avatarWidget,
      title: Text(
        contact['name'],
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: hasCooldown ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: hasCooldown
          ? Icon(Icons.lock_clock, color: Theme.of(context).colorScheme.onSurfaceVariant)
          : Checkbox(
              value: contact['selected'],
              activeColor: AppColors.gradientEnd,
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
                  title: Text('Cooldown Active'),
                  content: Text('You have $daysLeft more days cooldown before you can re-join or create a group chat with this friend.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('OK'),
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
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        radius: 24,
        child: Text(
          contact['name'].isNotEmpty ? contact['name'][0].toUpperCase() : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        contact['name'],
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(contact['phone']),
      trailing: TextButton(
        onPressed: () {
          _inviteOffPlatform(contact['phone']);
        },
        child: Text('Invite', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBottomActionArea() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
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
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gradientEnd,
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
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      behavior: SnackBarBehavior.floating,
                                      elevation: 0,
                                      duration: const Duration(milliseconds: 1500),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            ? SizedBox(
                                height: 20, 
                                width: 20, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              )
                            : Text(
                            'Add $_selectedCount to Group',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                  : SizedBox.shrink(),
            ),

            if (_selectedCount > 0) SizedBox(height: 16),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // Share Options Row (Spaced out evenly)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
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
                    iconWidget: Icon(
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant!,
                      size: 26,
                    ),
                    bgColor: Theme.of(context).colorScheme.onSurfaceVariant!.withValues(alpha: 0.1),
                    label: 'Copy Link',
                    onTap: () async {
                      await _shareGeneric();
                    },
                  ),
                  _buildShareIcon(
                    iconWidget: Icon(
                      Icons.share,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                      size: 26,
                    ),
                    bgColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
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
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _processContactsIsolate(Map<String, dynamic> args) {
  final simpleContacts = args['contacts'] as List<Map<String, String>>;
  final allUsers = args['users'] as List<Map<String, dynamic>>;
  final currentUserId = args['currentUserId'] as String;
  final activeCooldowns = args['cooldowns'] as Map<String, DateTime>;

  String cleanPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  final userPhoneMap = <String, Map<String, dynamic>>{};
  for (var u in allUsers) {
    if (u['uid'] == currentUserId) continue;
    final uPhone = (u['phone'] ?? '') as String;
    final cleanUPhone = cleanPhone(uPhone);
    if (cleanUPhone.length >= 7) {
      for (int i = 7; i <= cleanUPhone.length && i <= 12; i++) {
        userPhoneMap[cleanUPhone.substring(cleanUPhone.length - i)] = u;
      }
    }
  }

  List<Map<String, dynamic>> onPlat = [];
  List<Map<String, dynamic>> offPlat = [];
  Set<String> addedUserIds = {};

  for (var contact in simpleContacts) {
    final rawPhone = contact['phone'] ?? '';
    final name = contact['name'] ?? '';
    final cleanContactPhone = cleanPhone(rawPhone);

    bool matched = false;
    if (cleanContactPhone.length >= 7) {
      for (int i = cleanContactPhone.length > 12 ? 12 : cleanContactPhone.length; i >= 7; i--) {
        final testPhone = cleanContactPhone.substring(cleanContactPhone.length - i);
        if (userPhoneMap.containsKey(testPhone)) {
          final u = userPhoneMap[testPhone]!;
          if (!addedUserIds.contains(u['uid'])) {
             String displayName = name.isNotEmpty 
                 ? name 
                 : (u['displayName'] != null && (u['displayName'] as String).isNotEmpty ? u['displayName'] : 'Unknown');

             onPlat.add({
               'id': u['uid'],
               'name': displayName,
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

    if (!matched && rawPhone.isNotEmpty) {
      offPlat.add({'name': name, 'phone': rawPhone});
    }
  }

  onPlat.sort((a, b) {
    final DateTime? cdA = a['cooldownDate'];
    final DateTime? cdB = b['cooldownDate'];
    
    if (cdA == null && cdB == null) return (a['name'] as String).compareTo(b['name'] as String);
    if (cdA == null) return -1;
    if (cdB == null) return 1;
    
    return cdB.compareTo(cdA);
  });

  return {
    'onPlat': onPlat,
    'offPlat': offPlat,
  };
}

enum _ItemType { header, onPlatform, offPlatform, spacer }

class _ContactListItem {
  final _ItemType type;
  final Map<String, dynamic>? contact;
  final String? headerTitle;

  const _ContactListItem({
    required this.type,
    this.contact,
    this.headerTitle,
  });
}
