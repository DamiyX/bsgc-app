import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme.dart';
import 'edit_profile_screen.dart';
import 'tts_settings_screen.dart';
import 'support_chat_screen.dart';
import 'about_platform_screen.dart';
import 'faq_screen.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '2.1 MVP';
  bool _muteAppSounds = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _muteAppSounds = prefs.getBool('mute_app_sounds') ?? false;
    });
  }

  Future<void> _toggleMuteAppSounds(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mute_app_sounds', value);
    setState(() {
      _muteAppSounds = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('Account'),
          ListTile(
            leading: Icon(Icons.edit),
            title: Text('Edit Profile'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),

          Divider(),
          _buildSectionHeader('Preferences'),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.dark_mode_outlined),
                    title: Text('Theme Appearance'),
                    trailing: DropdownButton<ThemeMode>(
                      value: themeProvider.themeMode,
                      underline: SizedBox(),
                      onChanged: (ThemeMode? newMode) {
                        if (newMode != null) {
                          themeProvider.setThemeMode(newMode);
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Light'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Dark'),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.format_color_fill),
                    title: Text('Chat Bubble Theme'),
                    subtitle: Text('Choose how messages look'),
                    trailing: DropdownButton<ChatBubbleTheme>(
                      value: themeProvider.chatBubbleTheme,
                      onChanged: (ChatBubbleTheme? newValue) {
                        if (newValue != null) {
                          themeProvider.setChatBubbleTheme(newValue);
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ChatBubbleTheme.gradient,
                          child: Text('Gradient Purple'),
                        ),
                        DropdownMenuItem(
                          value: ChatBubbleTheme.solidPurple,
                          child: Text('Solid Purple'),
                        ),
                        DropdownMenuItem(
                          value: ChatBubbleTheme.darkGray,
                          child: Text('Dark Gray'),
                        ),
                        DropdownMenuItem(
                          value: ChatBubbleTheme.lightGray,
                          child: Text('Light Gray'),
                        ),
                        DropdownMenuItem(
                          value: ChatBubbleTheme.dark,
                          child: Text('Dark'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
          ),
          SwitchListTile(
            secondary: Icon(Icons.volume_off_outlined),
            title: Text('Mute App Sounds'),
            subtitle: Text('Turn off interaction sounds (e.g., likes, saves)'),
            value: _muteAppSounds,
            onChanged: _toggleMuteAppSounds,
            activeColor: AppColors.primary,
          ),
          ListTile(
            leading: Icon(Icons.record_voice_over),
            title: Text('Reading Voice'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TtsSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.volume_off_outlined),
            title: Text('Mute Contacts'),
            onTap: () {},
          ),

          Divider(),
          _buildSectionHeader('Support'),
          ListTile(
            leading: Icon(Icons.help_outline),
            title: Text('Help & Support'),
            subtitle: Text('Contact us or view FAQs'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportChatScreen()),
              );
            },
          ),

          Divider(),
          _buildSectionHeader('Spiritual Tools'),
          ListTile(
            leading: Icon(Icons.alarm),
            title: Text('Set Prayer Time / Alarm'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Prayer alarm coming soon')),
              );
            },
          ),

          Divider(),
          _buildSectionHeader('Data & Backup'),
          ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('Back up to Google Drive'),
            subtitle: Text('Save notes, insights, and profile to Drive'),
            onTap: () async {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Beta Testing Notice'),
                  content: const Text(
                    'We are currently in beta! When you connect your Google Drive, Google may show a warning saying this app isn\'t verified yet.\n\nJust click "Advanced" and then "Continue" to safely enable backups.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Proceed'),
                    ),
                  ],
                ),
              );

              if (proceed != true) return;

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Starting backup to Google Drive...'),
                  ),
                );
              }
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
            leading: Icon(Icons.cloud_download_outlined),
            title: Text('Restore from Google Drive'),
            subtitle: Text('Restore previously backed up data'),
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

          Divider(),
          _buildSectionHeader('About'),
          ListTile(
            leading: Icon(Icons.question_answer_outlined),
            title: Text('FAQs'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FaqScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About Platform'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPlatformScreen()),
              );
            },
          ),

          Divider(),
          _buildSectionHeader('Danger Zone'),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red),
            title: Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Account deletion requires re-auth.'),
                ),
              );
            },
          ),
          if (_appVersion.isNotEmpty) ...[
            SizedBox(height: 16),
            Center(
              child: Text(
                'Version $_appVersion',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
