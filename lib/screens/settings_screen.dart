import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import 'about_platform_screen.dart';
import 'edit_profile_screen.dart';
import 'faq_screen.dart';
import 'tts_settings_screen.dart';
import 'safety_center_screen.dart';
import 'legal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  bool _muteAppSounds = false;
  bool _notificationsEnabled = false;
  bool _messageNotifications = true;
  bool _insightNotifications = true;
  bool _previewNotificationContent = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      PackageInfo.fromPlatform(),
      NotificationService().loadPreferences(),
    ]);
    if (!mounted) return;
    final preferences = results[0] as SharedPreferences;
    final package = results[1] as PackageInfo;
    final notificationPreferences = results[2] as Map<String, bool>;
    setState(() {
      _muteAppSounds = preferences.getBool('mute_app_sounds') ?? false;
      _appVersion = '${package.version} (${package.buildNumber})';
      _notificationsEnabled = notificationPreferences['enabled'] ?? true;
      _messageNotifications = notificationPreferences['messages'] ?? true;
      _insightNotifications = notificationPreferences['insights'] ?? true;
      _previewNotificationContent =
          notificationPreferences['preview'] ?? false;
    });
  }

  Future<void> _saveNotificationPreferences() async {
    try {
      await NotificationService().updatePreferences(
        enabled: _notificationsEnabled,
        messages: _messageNotifications,
        insights: _insightNotifications,
        previewContent: _previewNotificationContent,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification settings could not be saved.'),
          ),
        );
      }
    }
  }

  Future<void> _toggleMuteAppSounds(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('mute_app_sounds', value);
    if (mounted) setState(() => _muteAppSounds = value);
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your profile, private notes, saved '
              'items, reflections, and account media. It cannot be undone.\n\n'
              'You must transfer ownership of shared studies first.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim() == 'DELETE',
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await AccountService().deleteCurrentAccount();
      await AuthService().signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Edit profile'),
            subtitle: const Text('Name, photo, and introduction'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),
          _section('Appearance and reading'),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) => ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Appearance'),
              trailing: DropdownButton<ThemeMode>(
                value: themeProvider.themeMode,
                underline: const SizedBox.shrink(),
                onChanged: (mode) {
                  if (mode != null) themeProvider.setThemeMode(mode);
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
          ),
          SwitchListTile(
            secondary: const Icon(Icons.music_off_outlined),
            title: const Text('Mute interaction sounds'),
            subtitle: const Text('Voice-note playback is not affected'),
            value: _muteAppSounds,
            onChanged: _toggleMuteAppSounds,
          ),
          _section('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications on this device'),
            subtitle: const Text(
              'The system permission can also be changed in device settings',
            ),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              _saveNotificationPreferences();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.forum_outlined),
            title: const Text('Study group messages'),
            value: _messageNotifications,
            onChanged: _notificationsEnabled
                ? (value) {
                    setState(() => _messageNotifications = value);
                    _saveNotificationPreferences();
                  }
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline_rounded),
            title: const Text('Contacts’ Insights'),
            value: _insightNotifications,
            onChanged: _notificationsEnabled
                ? (value) {
                    setState(() => _insightNotifications = value);
                    _saveNotificationPreferences();
                  }
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Show content on lock screen'),
            subtitle: const Text(
              'Off hides message and reflection text in notifications',
            ),
            value: _previewNotificationContent,
            onChanged: _notificationsEnabled
                ? (value) {
                    setState(() => _previewNotificationContent = value);
                    _saveNotificationPreferences();
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Bible reading voice'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TtsSettingsScreen()),
            ),
          ),
          _section('Privacy, storage, and safety'),
          ListTile(
            leading: const Icon(Icons.contacts_outlined),
            title: const Text('Contact privacy'),
            subtitle: const Text(
              'Braid does not upload or match your address book',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear temporary image memory'),
            subtitle: const Text('Does not delete your saved reflections'),
            onTap: () {
              PaintingBinding.instance.imageCache
                ..clear()
                ..clearLiveImages();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Temporary image memory cleared.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Safety controls'),
            subtitle: const Text('Review blocked accounts'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SafetyCenterScreen()),
            ),
          ),
          _section('About'),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('Frequently asked questions'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FaqScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About Braid'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPlatformScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy notice'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalScreen(
                  document: LegalDocument.privacy,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Community terms'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalScreen(
                  document: LegalDocument.terms,
                ),
              ),
            ),
          ),
          _section('Account actions'),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: colorScheme.error),
            title: Text('Log out', style: TextStyle(color: colorScheme.error)),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
            },
          ),
          ListTile(
            enabled: !_isDeletingAccount,
            leading: Icon(
              Icons.delete_forever_outlined,
              color: colorScheme.error,
            ),
            title: Text(
              _isDeletingAccount ? 'Deleting account…' : 'Delete account',
              style: TextStyle(color: colorScheme.error),
            ),
            subtitle: const Text('Permanent and irreversible'),
            onTap: _isDeletingAccount ? null : _deleteAccount,
          ),
          if (_appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Braid $_appVersion',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppColors.gradientEnd,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
