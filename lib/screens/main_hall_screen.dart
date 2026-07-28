import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/group_model.dart';
import '../models/insight_model.dart';
import '../models/note_model.dart';
import '../services/chat_service.dart';
import '../services/deep_link_service.dart';
import '../services/note_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/braid_media.dart';
import '../widgets/insights_row.dart';
import '../widgets/note_card.dart';
import 'create_group_screen.dart';
import 'create_insight_screen.dart';
import 'create_note_screen.dart';
import 'profile_screen.dart';
import 'safety_center_screen.dart';
import 'settings_screen.dart';
import 'study_room_screen.dart';
import 'view_insight_screen.dart';

class MainHallScreen extends StatefulWidget {
  const MainHallScreen({super.key});

  @override
  State<MainHallScreen> createState() => _MainHallScreenState();
}

class _MainHallScreenState extends State<MainHallScreen> {
  final ChatService _chatService = ChatService();
  final DeepLinkService _deepLinkService = DeepLinkService();
  final NotificationService _notificationService = NotificationService();
  final NoteService _noteService = NoteService();
  final TextEditingController _journalSearchController =
      TextEditingController();

  late final Stream<List<GroupModel>> _groupsStream;
  List<GroupModel>? _cachedGroups;
  int _selectedIndex = 0;
  bool _isRedeemingInvite = false;
  bool _showNotificationOffer = false;
  bool _enablingNotifications = false;
  String _journalQuery = '';

  @override
  void initState() {
    super.initState();
    _groupsStream = _chatService.getUserGroups();
    unawaited(_initializeNotifications());
    _deepLinkService.pendingInviteToken.addListener(_onPendingInviteChanged);
    _notificationService.destination.addListener(
      _onNotificationDestinationChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_redeemPendingInvite());
      unawaited(_openNotificationDestination());
    });
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.init();
      final shouldOffer = await _notificationService.shouldOfferPermission();
      if (mounted) setState(() => _showNotificationOffer = shouldOffer);
    } catch (_) {
      // Notification availability must never block the rest of the study app.
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() => _enablingNotifications = true);
    try {
      await _notificationService.updatePreferences(
        enabled: true,
        messages: true,
        insights: true,
        previewContent: false,
      );
      if (mounted) setState(() => _showNotificationOffer = false);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Notification permission was not enabled. You can retry in Settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _enablingNotifications = false);
    }
  }

  Future<void> _dismissNotificationOffer() async {
    await _notificationService.dismissPermissionOffer();
    if (mounted) setState(() => _showNotificationOffer = false);
  }

  @override
  void dispose() {
    _deepLinkService.pendingInviteToken.removeListener(_onPendingInviteChanged);
    _notificationService.destination.removeListener(
      _onNotificationDestinationChanged,
    );
    _journalSearchController.dispose();
    super.dispose();
  }

  void _onPendingInviteChanged() {
    if (_deepLinkService.pendingInviteToken.value != null) {
      unawaited(_redeemPendingInvite());
    }
  }

  void _onNotificationDestinationChanged() {
    if (_notificationService.destination.value != null) {
      unawaited(_openNotificationDestination());
    }
  }

  Future<void> _openNotificationDestination() async {
    if (!mounted) return;
    final destination = _notificationService.destination.value;
    final groupId = destination?.groupId;
    final insightId = destination?.insightId;
    if ((groupId == null || groupId.isEmpty) &&
        (insightId == null || insightId.isEmpty)) {
      return;
    }
    _notificationService.destination.value = null;

    try {
      if (groupId != null && groupId.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .get();
        if (!snapshot.exists || !mounted) return;
        await _openGroup(GroupModel.fromFirestore(snapshot));
      } else if (insightId != null && insightId.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('insights')
            .doc(insightId)
            .get();
        if (!snapshot.exists || !mounted) return;
        final insight = InsightModel.fromFirestore(snapshot);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewInsightScreen(
              userInsightsGroups: [
                [insight],
              ],
              initialUserIndex: 0,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage('That study update is not available right now.');
    }
  }

  Future<void> _redeemPendingInvite() async {
    if (_isRedeemingInvite || !mounted) return;
    final token = await _deepLinkService.getPendingInviteToken();
    if (token == null || !mounted) return;

    setState(() => _isRedeemingInvite = true);
    try {
      final redemption = await _chatService.redeemGroupInvite(token);
      await _deepLinkService.clearPendingInviteToken(token);
      if (!mounted) return;
      _showMessage(
        redemption.alreadyMember
            ? 'You are already in this study group.'
            : 'You joined the study group.',
      );
      setState(() => _selectedIndex = 1);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'We could not use that invite. Check your connection or ask for a new link.',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _redeemPendingInvite,
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _isRedeemingInvite = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openGroup(GroupModel group) async {
    unawaited(_chatService.resetUnreadCount(group.id));
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudyRoomScreen(group: group)),
    );
  }

  Future<void> _createGroup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(chatService: _chatService),
      ),
    );
  }

  Future<void> _openReflectionComposer(List<GroupModel> groups) async {
    final activeGroups = groups
        .where((group) => group.lifecycle == 'active')
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where should this reflection live?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The audience stays explicit. You can keep a thought private before choosing to share it.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _AudienceChoice(
                icon: Icons.lock_outline_rounded,
                title: 'Only me',
                description: 'Write a private journal reflection.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateNoteScreen(),
                    ),
                  );
                },
              ),
              _AudienceChoice(
                icon: Icons.people_outline_rounded,
                title: 'Study contacts',
                description:
                    'Share an Insight with people you have intentionally connected with.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateInsightScreen(),
                    ),
                  );
                },
              ),
              _AudienceChoice(
                icon: Icons.groups_2_outlined,
                title: 'A study group',
                description: activeGroups.isEmpty
                    ? 'Join or create a group before sharing there.'
                    : 'Choose a group, then add your reflection to its discussion.',
                enabled: activeGroups.isNotEmpty,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final selected = await _chooseGroup(activeGroups);
                  if (selected != null && mounted) await _openGroup(selected);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<GroupModel?> _chooseGroup(List<GroupModel> groups) {
    return showModalBottomSheet<GroupModel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Choose a study group',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final group in groups.where((item) => item.lifecycle == 'active'))
              ListTile(
                minTileHeight: 56,
                leading: BraidCoverImage(
                  identity: group.id,
                  imageUrl: group.photoUrl,
                  width: 44,
                  height: 44,
                  borderRadius: 10,
                  semanticLabel: '${group.name} cover',
                ),
                title: Text(group.name),
                subtitle: Text(_studyLabel(group)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, group),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Today', 'Groups', 'Journal', 'Me'];
    return StreamBuilder<List<GroupModel>>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) _cachedGroups = snapshot.data;
        final groups = _cachedGroups ?? const <GroupModel>[];
        final firstLoad =
            _cachedGroups == null &&
            snapshot.connectionState == ConnectionState.waiting;
        final firstError = snapshot.hasError && _cachedGroups == null;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              titles[_selectedIndex],
              style: const TextStyle(
                fontFamily: 'Comfortaa',
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              if (_isRedeemingInvite)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_selectedIndex == 3)
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: firstLoad
                ? const Center(child: CircularProgressIndicator())
                : firstError
                ? _LoadError(onRetry: () => setState(() {}))
                : IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildToday(groups, snapshot.hasError),
                      _buildGroups(groups),
                      _buildJournal(),
                      _buildMe(),
                    ],
                  ),
          ),
          floatingActionButton: _buildFloatingActionButton(groups),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (value) {
              setState(() => _selectedIndex = value);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.wb_sunny_outlined),
                selectedIcon: Icon(Icons.wb_sunny_rounded),
                label: 'Today',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_2_outlined),
                selectedIcon: Icon(Icons.groups_2_rounded),
                label: 'Groups',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: 'Journal',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Me',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildFloatingActionButton(List<GroupModel> groups) {
    switch (_selectedIndex) {
      case 0:
        return FloatingActionButton.extended(
          tooltip: 'Write a reflection',
          onPressed: () => _openReflectionComposer(groups),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Reflect'),
        );
      case 1:
        return FloatingActionButton.extended(
          tooltip: 'Create a study group',
          onPressed: _createGroup,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New group'),
        );
      case 2:
        return FloatingActionButton.extended(
          tooltip: 'Write a private reflection',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateNoteScreen()),
          ),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Write'),
        );
      default:
        return null;
    }
  }

  Widget _buildToday(List<GroupModel> groups, bool showingCachedData) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final activeGroups = groups
        .where((group) => group.lifecycle == 'active')
        .toList();
    final scheduledGroups = groups
        .where((group) => group.lifecycle == 'scheduled')
        .toList();
    final nextGroup = activeGroups.isNotEmpty
        ? activeGroups.first
        : (scheduledGroups.isNotEmpty ? scheduledGroups.first : null);

    return ListView(
      key: const PageStorageKey('today'),
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        if (showingCachedData)
          _StatusBanner(
            icon: Icons.cloud_off_outlined,
            text: 'Showing saved information while Braid reconnects.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A quiet place to notice, reflect, and grow together.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_showNotificationOffer)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Know when your study continues',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Not now',
                          onPressed: _dismissNotificationOffer,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enable private-by-default alerts for group messages and '
                      'contacts’ Insights. Message text stays hidden on the '
                      'lock screen unless you choose otherwise.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed:
                          _enablingNotifications ? null : _enableNotifications,
                      child: Text(
                        _enablingNotifications
                            ? 'Enabling…'
                            : 'Enable notifications',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (nextGroup != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: _NextStudyCard(
              group: nextGroup,
              progress: nextGroup.readingProgress[uid] ?? 0,
              onTap: () => _openGroup(nextGroup),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: _EmptyTodayCard(onCreateGroup: _createGroup),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Text(
            'From your study contacts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const InsightsRow(embedded: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: OutlinedButton.icon(
            onPressed: () => _openReflectionComposer(groups),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Start with a private reflection'),
          ),
        ),
      ],
    );
  }

  Widget _buildGroups(List<GroupModel> groups) {
    if (groups.isEmpty) {
      return _EmptyGroups(onCreate: _createGroup);
    }
    return ListView.separated(
      key: const PageStorageKey('groups'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _GroupCard(group: group, onTap: () => _openGroup(group));
      },
    );
  }

  Widget _buildJournal() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Sign in to open your journal.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SearchBar(
            controller: _journalSearchController,
            hintText: 'Search your reflections',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_journalQuery.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _journalSearchController.clear();
                    setState(() => _journalQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: (value) {
              setState(() => _journalQuery = value.trim().toLowerCase());
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<List<NoteModel>>(
            stream: _noteService.getUserNotes(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError && !snapshot.hasData) {
                return const _LoadError();
              }
              final notes = (snapshot.data ?? const <NoteModel>[])
                  .where(
                    (note) =>
                        _journalQuery.isEmpty ||
                        note.title.toLowerCase().contains(_journalQuery) ||
                        note.body.toLowerCase().contains(_journalQuery),
                  )
                  .toList();
              if (notes.isEmpty) {
                return _EmptyJournal(
                  hasSearch: _journalQuery.isNotEmpty,
                  onWrite: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateNoteScreen(),
                    ),
                  ),
                );
              }
              return ListView.builder(
                key: const PageStorageKey('journal'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                itemCount: notes.length,
                itemBuilder: (context, index) => NoteCard(
                  note: notes[index],
                  onDelete: () => _confirmDeleteNote(uid, notes[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteNote(String uid, NoteModel note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this reflection?'),
        content: const Text(
          'This removes it from your journal. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _noteService.deleteNote(uid, note.id);
    } catch (_) {
      if (mounted) _showMessage('Could not delete that reflection.');
    }
  }

  Widget _buildMe() {
    final user = FirebaseAuth.instance.currentUser;
    return ListView(
      key: const PageStorageKey('me'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Center(
          child: BraidAvatar(
            identity: user?.uid ?? 'me',
            displayName: user?.displayName ?? 'You',
            imageUrl: user?.photoURL,
            radius: 48,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          user?.displayName?.trim().isNotEmpty == true
              ? user!.displayName!.trim()
              : 'Your space',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your reflections stay private unless you deliberately share them.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        _MeDestination(
          icon: Icons.person_outline_rounded,
          title: 'Profile and saved items',
          description: 'Edit your identity and revisit saved Insights.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
        ),
        _MeDestination(
          icon: Icons.shield_outlined,
          title: 'Safety center',
          description: 'Review blocks, reports, and community controls.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SafetyCenterScreen(),
            ),
          ),
        ),
        _MeDestination(
          icon: Icons.settings_outlined,
          title: 'Settings',
          description: 'Privacy, notifications, storage, theme, and account.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

String _studyLabel(GroupModel group) {
  if (group.groupType == 'Bible') {
    return group.studyBook?.isNotEmpty == true
        ? group.studyBook!
        : 'Bible study';
  }
  return group.topic?.isNotEmpty == true ? group.topic! : 'Topic study';
}

String _lifecycleLabel(GroupModel group) {
  switch (group.lifecycle) {
    case 'scheduled':
      return group.startDate == null
          ? 'Starts soon'
          : 'Starts ${DateFormat('MMM d').format(group.startDate!)}';
    case 'completed':
      return 'Completed';
    case 'archived':
      return 'Archived';
    default:
      return 'In progress';
  }
}

class _NextStudyCard extends StatelessWidget {
  final GroupModel group;
  final double progress;
  final VoidCallback onTap;

  const _NextStudyCard({
    required this.group,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label:
          'Continue ${group.name}. ${_lifecycleLabel(group)}. ${(progress * 100).round()} percent complete.',
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.primaryContainer,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                BraidCoverImage(
                  identity: group.id,
                  imageUrl: group.photoUrl,
                  width: 72,
                  height: 88,
                  borderRadius: 12,
                  semanticLabel: '${group.name} cover',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.lifecycle == 'scheduled'
                            ? 'Your next study'
                            : 'Continue your study',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_studyLabel(group)} • ${_lifecycleLabel(group)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final GroupModel group;
  final VoidCallback onTap;

  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final progress = group.readingProgress[uid] ?? 0;
    final unread = group.unreadCounts[uid] ?? 0;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              BraidCoverImage(
                identity: group.id,
                imageUrl: group.photoUrl,
                width: 64,
                height: 76,
                borderRadius: 12,
                semanticLabel: '${group.name} study cover',
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (unread > 0)
                          Semantics(
                            label: '$unread unread messages',
                            child: Badge(label: Text('$unread')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_studyLabel(group)} • ${_lifecycleLabel(group)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  const _AudienceChoice({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      minTileHeight: 68,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: enabled ? onTap : null,
    );
  }
}

class _MeDestination extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _MeDestination({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        minTileHeight: 72,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatusBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<BraidSemanticColors>();
    return MaterialBanner(
      leading: Icon(icon, color: semantic?.offline),
      content: Text(text),
      actions: const [SizedBox.shrink()],
    );
  }
}

class _LoadError extends StatelessWidget {
  final VoidCallback? onRetry;

  const _LoadError({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Braid could not load this yet.',
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyTodayCard extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const _EmptyTodayCard({required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              'Begin with a simple plan',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a study circle, choose a Bible book or topic, and invite people when you are ready.',
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onCreateGroup,
              child: const Text('Create a study group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyGroups({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_2_outlined, size: 52),
            const SizedBox(height: 14),
            Text(
              'Study is better with intention',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a circle or open a trusted invite link to join one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onCreate, child: const Text('Create group')),
          ],
        ),
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onWrite;

  const _EmptyJournal({required this.hasSearch, required this.onWrite});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasSearch ? Icons.search_off_rounded : Icons.edit_note_rounded,
                size: 50),
            const SizedBox(height: 12),
            Text(
              hasSearch ? 'No matching reflections' : 'Your journal is quiet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try another word or clear the search.'
                  : 'Capture what stood out before the moment passes.',
              textAlign: TextAlign.center,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onWrite, child: const Text('Write')),
            ],
          ],
        ),
      ),
    );
  }
}
