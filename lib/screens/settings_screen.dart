import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/device_settings_service.dart';
import '../services/notification_service.dart';
import '../services/user_facing_error_copy.dart';
import '../theme.dart';
import 'about_platform_screen.dart';
import 'edit_profile_screen.dart';
import 'faq_screen.dart';
import 'tts_settings_screen.dart';
import 'safety_center_screen.dart';
import 'legal_screen.dart';

Future<bool> persistMuteAppSoundsPreference(
  bool value, {
  Future<SharedPreferences> Function()? loadPreferences,
}) async {
  try {
    final preferences =
        await (loadPreferences ?? SharedPreferences.getInstance)();
    return await preferences.setBool('mute_app_sounds', value);
  } catch (_) {
    return false;
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  String _appVersion = '';
  bool _muteAppSounds = false;
  bool _notificationsEnabled = false;
  bool _messageNotifications = true;
  bool _insightNotifications = true;
  bool _previewNotificationContent = false;
  bool _notificationPermissionDenied = false;
  bool _isSavingNotifications = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      PackageInfo.fromPlatform(),
      NotificationService().loadPreferences(),
      NotificationService().getDevicePermission(),
    ]);
    if (!mounted) return;
    final preferences = results[0] as SharedPreferences;
    final package = results[1] as PackageInfo;
    final notificationPreferences = results[2] as Map<String, bool>;
    final permission = results[3] as DeviceNotificationPermission;
    final notificationDecision = resolveNotificationPreference(
      requestedEnabled: notificationPreferences['enabled'] ?? false,
      permission: permission,
    );
    setState(() {
      _muteAppSounds = preferences.getBool('mute_app_sounds') ?? false;
      _appVersion = '${package.version} (${package.buildNumber})';
      _notificationsEnabled = notificationDecision.enabled;
      _notificationPermissionDenied =
          notificationDecision.shouldOpenSystemSettings;
      _messageNotifications = notificationPreferences['messages'] ?? true;
      _insightNotifications = notificationPreferences['insights'] ?? true;
      _previewNotificationContent = notificationPreferences['preview'] ?? false;
    });
  }

  Future<void> _updateNotificationPreferences({
    bool? enabled,
    bool? messages,
    bool? insights,
    bool? previewContent,
  }) async {
    if (_isSavingNotifications) return;
    final previous = (
      enabled: _notificationsEnabled,
      messages: _messageNotifications,
      insights: _insightNotifications,
      preview: _previewNotificationContent,
      permissionDenied: _notificationPermissionDenied,
    );
    setState(() {
      _isSavingNotifications = true;
      _notificationsEnabled = enabled ?? _notificationsEnabled;
      _messageNotifications = messages ?? _messageNotifications;
      _insightNotifications = insights ?? _insightNotifications;
      _previewNotificationContent =
          previewContent ?? _previewNotificationContent;
    });
    try {
      final decision = await NotificationService().updatePreferences(
        enabled: _notificationsEnabled,
        messages: _messageNotifications,
        insights: _insightNotifications,
        previewContent: _previewNotificationContent,
      );
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = decision.enabled;
        _notificationPermissionDenied = decision.shouldOpenSystemSettings;
      });
      if (!decision.enabled && enabled == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision.shouldOpenSystemSettings
                  ? 'Notifications are blocked by device settings and remain off.'
                  : 'Notification permission was not enabled.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = previous.enabled;
        _messageNotifications = previous.messages;
        _insightNotifications = previous.insights;
        _previewNotificationContent = previous.preview;
        _notificationPermissionDenied = previous.permissionDenied;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification settings could not be saved.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingNotifications = false);
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await DeviceSettingsService().openNotificationSettings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device notification settings could not be opened.'),
        ),
      );
    }
  }

  Future<void> _toggleMuteAppSounds(bool value) async {
    final previous = _muteAppSounds;
    if (mounted) setState(() => _muteAppSounds = value);
    if (!await persistMuteAppSoundsPreference(value)) {
      if (!mounted) return;
      setState(() => _muteAppSounds = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sound settings could not be saved. Try again.'),
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This starts a durable deletion process for your profile, '
              'private notes, saved items, reflections, and account media. '
              'It cannot be undone after processing begins.\n\n'
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
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final request = await AccountService().deleteCurrentAccount();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Deletion requested'),
          content: Text(
            'Your account deletion job is ${request.status}. Braid will '
            'continue the cleanup safely in the background.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      await AuthService().signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Account deletion request failed (${error.runtimeType}).');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accountDeletionErrorCopy(error))));
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
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
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
            subtitle: Text(
              _notificationPermissionDenied
                  ? 'Blocked by device settings. Enable Braid there before trying again.'
                  : 'The system permission can also be changed in device settings',
            ),
            value: _notificationsEnabled,
            onChanged: _isSavingNotifications
                ? null
                : (value) => _updateNotificationPreferences(enabled: value),
          ),
          if (_notificationPermissionDenied &&
              defaultTargetPlatform == TargetPlatform.android)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Open notification settings'),
              subtitle: const Text(
                'Allow Braid notifications, then return to this screen.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openNotificationSettings,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.forum_outlined),
            title: const Text('Study group messages'),
            value: _messageNotifications,
            onChanged: _notificationsEnabled && !_isSavingNotifications
                ? (value) => _updateNotificationPreferences(messages: value)
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline_rounded),
            title: const Text('Contacts’ Insights'),
            value: _insightNotifications,
            onChanged: _notificationsEnabled && !_isSavingNotifications
                ? (value) => _updateNotificationPreferences(insights: value)
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Show content on lock screen'),
            subtitle: const Text(
              'Off hides message and reflection text in notifications',
            ),
            value: _previewNotificationContent,
            onChanged: _notificationsEnabled && !_isSavingNotifications
                ? (value) =>
                      _updateNotificationPreferences(previewContent: value)
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
                const SnackBar(
                  content: Text('Temporary image memory cleared.'),
                ),
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
                builder: (_) =>
                    const LegalScreen(document: LegalDocument.privacy),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Community terms'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const LegalScreen(document: LegalDocument.terms),
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
