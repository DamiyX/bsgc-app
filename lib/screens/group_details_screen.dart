import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/group_model.dart';
import '../services/chat_service.dart';
import '../services/safety_service.dart';
import '../services/storage_service.dart';
import '../widgets/add_member_sheet.dart';
import '../widgets/braid_media.dart';
import '../widgets/report_dialog.dart';
import 'edit_group_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  final GroupModel group;

  const GroupDetailsScreen({super.key, required this.group});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final ChatService _chatService = ChatService();
  late GroupModel _group;
  StreamSubscription<DocumentSnapshot>? _groupSubscription;
  List<Map<String, dynamic>> _members = const [];
  bool _membersLoading = true;
  bool _memberLoadFailed = false;
  bool _isMuted = false;
  bool _coverBusy = false;
  bool _actionBusy = false;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isOwner => _group.ownerId == _currentUserId;
  bool get _canInvite =>
      _isOwner &&
      _group.members.length < 12 &&
      !const {'completed', 'archived'}.contains(_group.lifecycle);

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _groupSubscription = FirebaseFirestore.instance
        .collection('groups')
        .doc(_group.id)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists || !mounted) return;
            final previousMembers = _group.members.join('|');
            final updated = GroupModel.fromFirestore(snapshot);
            setState(() => _group = updated);
            if (updated.members.join('|') != previousMembers) {
              unawaited(_loadMembers());
            }
          },
          onError: (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Live study details are temporarily offline.'),
                ),
              );
            }
          },
        );
    unawaited(_loadMembers());
    unawaited(_loadMuteState());
  }

  Future<void> _loadMembers() async {
    if (mounted) {
      setState(() {
        _membersLoading = true;
        _memberLoadFailed = false;
      });
    }
    try {
      final members = await _chatService.getGroupMembersProfiles(
        _group.members,
      );
      if (mounted) setState(() => _members = members);
    } catch (_) {
      if (mounted) setState(() => _memberLoadFailed = true);
    } finally {
      if (mounted) setState(() => _membersLoading = false);
    }
  }

  Future<void> _loadMuteState() async {
    try {
      final muted = await _chatService.isGroupMuted(_group.id);
      if (mounted) setState(() => _isMuted = muted);
    } catch (_) {
      // The user can retry by toggling the setting.
    }
  }

  Future<void> _setMuted(bool value) async {
    final previous = _isMuted;
    setState(() => _isMuted = value);
    try {
      await _chatService.setGroupMuted(_group.id, value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isMuted = previous);
      _showMessage('The notification setting could not be saved.');
    }
  }

  Future<void> _inviteMember() async {
    if (!_canInvite) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMemberSheet(groupId: _group.id),
    );
  }

  Future<void> _editDetails() async {
    if (!_isOwner) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditGroupScreen(group: _group, chatService: _chatService),
      ),
    );
  }

  Future<void> _changeCover() async {
    if (!_isOwner || _coverBusy) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;

    setState(() => _coverBusy = true);
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        await image.readAsBytes(),
        minWidth: 700,
        minHeight: 700,
        quality: 78,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty || compressed.length > 5 * 1024 * 1024) {
        throw StateError('The selected image is too large.');
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in to update the cover.');
      final url = await StorageService.uploadGroupCover(
        bytes: compressed,
        groupId: _group.id,
        ownerId: user.uid,
      );
      await _chatService.editGroup(
        _group.id,
        _group.name,
        _group.pinnedScripture,
        description: _group.description,
        photoUrl: url,
      );
      if (mounted) _showMessage('Study cover updated.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'The cover could not be updated. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _extendStudy() async {
    if (!_isOwner || _actionBusy) return;
    final confirmed = await _confirm(
      title: 'Add 30 days?',
      message:
          'The end date will move forward by 30 days. A completed study will '
          'become active again. ${3 - _group.extensionCount} extension(s) '
          'remain.',
      action: 'Extend study',
    );
    if (!confirmed || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _chatService.extendGroupDuration(
        _group.id,
        const Duration(days: 30),
      );
      if (mounted) _showMessage('Study extended by 30 days.');
    } catch (_) {
      if (mounted) _showMessage('The study could not be extended.');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _archiveStudy() async {
    if (!_isOwner || _actionBusy) return;
    final confirmed = await _confirm(
      title: 'Archive this study?',
      message:
          'It will become read-only and leave the active Groups list for '
          'every member.',
      action: 'Archive',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _chatService.archiveGroup(_group.id);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (mounted) _showMessage('The study could not be archived.');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _leaveStudy() async {
    if (_isOwner || _actionBusy) return;
    final confirmed = await _confirm(
      title: 'Leave this study?',
      message: 'You will lose access to its private discussion and media.',
      action: 'Leave',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await _chatService.leaveGroup(_group.id);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (mounted) _showMessage('You could not leave this study.');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _memberAction(String action, String uid, String name) async {
    try {
      switch (action) {
        case 'transfer':
          final confirmed = await _confirm(
            title: 'Transfer ownership?',
            message:
                '$name will control invitations, members, and archiving. '
                'You will remain a member.',
            action: 'Transfer',
          );
          if (confirmed) {
            await _chatService.transferGroupOwnership(_group.id, uid);
          }
        case 'remove':
          final confirmed = await _confirm(
            title: 'Remove $name?',
            message: 'They will lose access to this private study.',
            action: 'Remove',
            destructive: true,
          );
          if (confirmed) {
            await _chatService.removeGroupMember(_group.id, uid);
          }
        case 'block':
          final confirmed = await _confirm(
            title: 'Block $name?',
            message:
                'Their contacts-only Insights will be hidden. Shared study '
                'content may remain visible.',
            action: 'Block',
            destructive: true,
          );
          if (confirmed) await SafetyService().blockUser(uid);
        case 'report':
          await showReportDialog(
            context,
            targetType: 'user',
            targetId: uid,
            groupId: _group.id,
          );
      }
    } catch (_) {
      if (mounted) _showMessage('That member action could not be completed.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _focusLabel {
    if (_group.groupType == 'Topic') {
      return _group.topic?.trim().isNotEmpty == true
          ? _group.topic!
          : 'Topic study';
    }
    return _group.studyBook?.trim().isNotEmpty == true
        ? _group.studyBook!
        : 'Bible study';
  }

  String get _dateLabel {
    final start = _group.startDate;
    final end = _group.endDate;
    if (start == null && end == null) return 'No study dates';
    final formatter = DateFormat('MMM d, yyyy');
    if (start == null) return 'Ends ${formatter.format(end!)}';
    if (end == null) return 'Started ${formatter.format(start)}';
    return '${formatter.format(start)} – ${formatter.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Study details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      BraidCoverImage(
                        identity: _group.id,
                        imageUrl: _group.photoUrl,
                        width: 104,
                        height: 104,
                        semanticLabel: '${_group.name} study cover',
                      ),
                      if (_isOwner)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Change study cover',
                            onPressed: _coverBusy ? null : _changeCover,
                            icon: _coverBusy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_outlined),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _group.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _focusLabel,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LifecycleChip(lifecycle: _group.lifecycle),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Study dates'),
                  subtitle: Text(_dateLabel),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline_rounded),
                  title: const Text('Capacity'),
                  subtitle: Text('${_group.members.length} of 12 people'),
                ),
                if (_group.description.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.subject_rounded),
                    title: const Text('About this study'),
                    subtitle: Text(_group.description),
                  ),
                if (_group.pinnedScripture.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline_rounded),
                    title: const Text('Pinned Scripture'),
                    subtitle: Text(_group.pinnedScripture),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Message notifications'),
              subtitle: const Text('This setting applies only to this study'),
              value: _isMuted == false,
              onChanged: (enabled) => _setMuted(!enabled),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'People',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_canInvite)
                FilledButton.tonalIcon(
                  onPressed: _inviteMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Invite'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_membersLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_memberLoadFailed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('People could not be refreshed'),
                subtitle: const Text(
                  'Previously cached study access is not changed.',
                ),
                trailing: IconButton(
                  tooltip: 'Retry',
                  onPressed: _loadMembers,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [for (final member in _members) _memberTile(member)],
              ),
            ),
          const SizedBox(height: 24),
          Text(
            _isOwner ? 'Owner controls' : 'Study membership',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                if (_isOwner && _group.lifecycle != 'archived')
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit name and description'),
                    onTap: _editDetails,
                  ),
                if (_isOwner &&
                    _group.lifecycle != 'archived' &&
                    _group.extensionCount < 3)
                  ListTile(
                    enabled: !_actionBusy,
                    leading: const Icon(Icons.event_repeat_rounded),
                    title: const Text('Extend by 30 days'),
                    subtitle: Text(
                      '${3 - _group.extensionCount} extension(s) remaining',
                    ),
                    onTap: _extendStudy,
                  ),
                if (_isOwner && _group.lifecycle == 'archived')
                  const ListTile(
                    leading: Icon(Icons.lock_outline_rounded),
                    title: Text('Archived and read-only'),
                    subtitle: Text(
                      'This study remains available as a completed record.',
                    ),
                  ),
                if (!_isOwner || _group.lifecycle != 'archived')
                  ListTile(
                    enabled: !_actionBusy,
                    leading: Icon(
                      _isOwner
                          ? Icons.archive_outlined
                          : Icons.exit_to_app_rounded,
                      color: colorScheme.error,
                    ),
                    title: Text(
                      _isOwner ? 'Archive study' : 'Leave study',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    subtitle: _isOwner
                        ? const Text(
                            'Members keep read-only access to the record',
                          )
                        : null,
                    onTap: _isOwner ? _archiveStudy : _leaveStudy,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member) {
    final uid = member['uid']?.toString() ?? '';
    final name = member['displayName']?.toString().trim().isNotEmpty == true
        ? member['displayName'].toString()
        : 'Braid member';
    final photoUrl = member['photoURL']?.toString();
    final isSelf = uid == _currentUserId;
    final isGroupOwner = uid == _group.ownerId;

    return ListTile(
      leading: BraidAvatar(
        identity: uid,
        displayName: name,
        imageUrl: photoUrl,
        radius: 22,
      ),
      title: Text(name),
      subtitle: isGroupOwner || isSelf
          ? Text([if (isGroupOwner) 'Owner', if (isSelf) 'You'].join(' · '))
          : null,
      trailing: isSelf
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Actions for $name',
              onSelected: (action) => _memberAction(action, uid, name),
              itemBuilder: (_) => [
                if (_isOwner) ...[
                  const PopupMenuItem(
                    value: 'transfer',
                    child: Text('Transfer ownership'),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from study'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'block',
                  child: Text('Block account'),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report account'),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _groupSubscription?.cancel();
    super.dispose();
  }
}

class _LifecycleChip extends StatelessWidget {
  final String lifecycle;

  const _LifecycleChip({required this.lifecycle});

  @override
  Widget build(BuildContext context) {
    final label = switch (lifecycle) {
      'draft' => 'Draft',
      'scheduled' => 'Scheduled',
      'completed' => 'Completed',
      'archived' => 'Archived',
      _ => 'Active',
    };
    final icon = switch (lifecycle) {
      'scheduled' => Icons.schedule_rounded,
      'completed' => Icons.check_circle_outline_rounded,
      'archived' => Icons.archive_outlined,
      _ => Icons.play_circle_outline_rounded,
    };
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
