import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme.dart';
import 'edit_profile_screen.dart';
import 'tts_settings_screen.dart';
import 'support_chat_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Profile'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),

          const Divider(),
          _buildSectionHeader('Preferences'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark Mode'),
            value: false, // Simulated
            onChanged: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dark mode toggle coming soon')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Reading Voice'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TtsSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_off_outlined),
            title: const Text('Mute Contacts'),
            onTap: () {},
          ),

          const Divider(),
          _buildSectionHeader('Support'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            subtitle: const Text('Contact us or view FAQs'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportChatScreen()),
              );
            },
          ),

          const Divider(),
          _buildSectionHeader('Spiritual Tools'),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Set Prayer Time / Alarm'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Prayer alarm coming soon')),
              );
            },
          ),

          const Divider(),
          _buildSectionHeader('Data & Backup'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Back up to Google Drive'),
            subtitle: const Text('Save notes, insights, and profile to Drive'),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Starting backup to Google Drive...'),
                ),
              );
              try {
                await BackupService().backupToGoogleDrive();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Backup successful!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Restore from Google Drive'),
            subtitle: const Text('Restore previously backed up data'),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Starting restore from Google Drive...'),
                ),
              );
              try {
                await BackupService().restoreFromGoogleDrive();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Restore successful!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
                }
              }
            },
          ),

          const Divider(),
          _buildSectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Feedback'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Platform'),
            onTap: () {},
          ),

          const Divider(),
          _buildSectionHeader('Danger Zone'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deletion requires re-auth.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
