import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme.dart';

class AddMemberSheet extends StatefulWidget {
  final String groupId;

  const AddMemberSheet({Key? key, required this.groupId}) : super(key: key);

  @override
  _AddMemberSheetState createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  bool _isLoading = true;
  bool _permissionDenied = false;

  List<Map<String, dynamic>> _onPlatformContacts = [];
  List<Map<String, dynamic>> _offPlatformContacts = [];

  int get _selectedCount => _onPlatformContacts.where((c) => c['selected'] == true).length;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    if (await FlutterContacts.requestPermission()) {
      List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
      
      // For simulation, we'll assign the first 3 contacts that have phones to "On Platform"
      // and the rest to "Other Contacts".
      List<Map<String, dynamic>> onPlat = [];
      List<Map<String, dynamic>> offPlat = [];

      for (var contact in contacts) {
        if (contact.phones.isNotEmpty) {
          final String phone = contact.phones.first.number;
          final String name = contact.displayName;
          
          if (onPlat.length < 3) {
            onPlat.add({
              'id': 'u_${contact.id}',
              'name': name,
              // Fallback default avatar for simulated platform users
              'photo': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&q=80',
              'selected': false,
            });
          } else {
            offPlat.add({
              'name': name,
              'phone': phone,
            });
          }
        }
      }

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

  Future<void> _shareGeneric() async {
    await Share.share('Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}');
  }

  Future<void> _shareWhatsApp() async {
    final text = Uri.encodeComponent('Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}');
    final url = Uri.parse('whatsapp://send?text=$text');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp is not installed.')));
    }
  }

  Future<void> _shareEmail() async {
    final subject = Uri.encodeComponent('Join me on Braid!');
    final body = Uri.encodeComponent('Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}');
    final url = Uri.parse('mailto:?subject=$subject&body=$body');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email client configured.')));
    }
  }

  void _inviteOffPlatform(String phone) async {
    final text = Uri.encodeComponent('Join my Bible study group on Braid! https://braidapp.com/join/${widget.groupId}');
    final url = Uri.parse('sms:$phone?body=$text');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open SMS app.')));
    }
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
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _permissionDenied
                        ? const Center(child: Text('Contact permissions denied.'))
                        : SingleChildScrollView(
                            controller: scrollController,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_onPlatformContacts.isNotEmpty) ...[
                                  _buildSectionHeader('On Braid'),
                                  ..._onPlatformContacts.map((contact) => _buildOnPlatformTile(contact)).toList(),
                                  const SizedBox(height: 16),
                                ],
                                _buildSectionHeader('Other Contacts'),
                                ..._offPlatformContacts.map((contact) => _buildOffPlatformTile(contact)).toList(),
                                const SizedBox(height: 100), // padding for bottom bar
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundImage: NetworkImage(contact['photo']),
        radius: 24,
      ),
      title: Text(contact['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Checkbox(
        value: contact['selected'],
        activeColor: AppColors.primary,
        onChanged: (val) {
          setState(() {
            contact['selected'] = val;
          });
        },
      ),
      onTap: () {
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
          style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(contact['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(contact['phone']),
      trailing: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[100],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          )
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Added $_selectedCount members to group')),
                            );
                          },
                          child: Text(
                            'Add $_selectedCount to Group',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            
            if (_selectedCount > 0)
              const SizedBox(height: 16),
              
            const Divider(height: 1, color: Colors.black12),
            
            // Share Options Row (Spaced out evenly)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildShareIcon(
                    iconWidget: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 26),
                    bgColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                    label: 'WhatsApp',
                    onTap: _shareWhatsApp,
                  ),
                  _buildShareIcon(
                    iconWidget: const Icon(Icons.email_outlined, color: Colors.blue, size: 26),
                    bgColor: Colors.blue.withValues(alpha: 0.1),
                    label: 'Email',
                    onTap: _shareEmail,
                  ),
                  _buildShareIcon(
                    iconWidget: Icon(Icons.link, color: Colors.grey[700]!, size: 26),
                    bgColor: Colors.grey[700]!.withValues(alpha: 0.1),
                    label: 'Copy Link',
                    onTap: () async {
                      await _shareGeneric();
                    },
                  ),
                  _buildShareIcon(
                    iconWidget: const Icon(Icons.share, color: Colors.black87, size: 26),
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

  Widget _buildShareIcon({required Widget iconWidget, required Color bgColor, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
