import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/chat_service.dart';
import '../theme.dart';

class AddMemberSheet extends StatefulWidget {
  final String groupId;

  const AddMemberSheet({super.key, required this.groupId});

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final ChatService _chatService = ChatService();
  GroupInvite? _invite;
  bool _isCreating = false;
  String? _errorMessage;
  int _expiresInHours = 72;
  int _maxUses = 1;

  Future<void> _createInvite() async {
    if (_isCreating) return;
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final invite = await _chatService.createGroupInvite(
        widget.groupId,
        expiresInHours: _expiresInHours,
        maxUses: _maxUses,
      );
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  String _shareMessage(GroupInvite invite) {
    final expiry = DateFormat('MMM d, h:mm a').format(invite.expiresAt);
    return 'Join my Bible study on Braid.\n\n'
        '${invite.joinUrl}\n\n'
        'This private invitation expires $expiry.';
  }

  Future<void> _copyInvite() async {
    final invite = _invite;
    if (invite == null) return;
    await Clipboard.setData(ClipboardData(text: invite.joinUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Private invitation copied.')),
    );
  }

  Future<void> _shareInvite() async {
    final invite = _invite;
    if (invite == null) return;
    await Share.share(_shareMessage(invite));
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Invite someone you trust',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Braid creates a private, expiring invitation. The link does '
                'not contain the group ID and joining is checked securely.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (invite == null) ...[
                DropdownButtonFormField<int>(
                  initialValue: _expiresInHours,
                  decoration: const InputDecoration(
                    labelText: 'Invitation expires',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('In 24 hours')),
                    DropdownMenuItem(value: 72, child: Text('In 3 days')),
                    DropdownMenuItem(value: 168, child: Text('In 7 days')),
                  ],
                  onChanged: _isCreating
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _expiresInHours = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _maxUses,
                  decoration: const InputDecoration(
                    labelText: 'Number of people',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    11,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                        index == 0 ? 'One person' : '${index + 1} people',
                      ),
                    ),
                  ),
                  onChanged: _isCreating
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _maxUses = value);
                          }
                        },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isCreating ? null : _createInvite,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gradientEnd,
                    ),
                    icon: _isCreating
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(
                      _isCreating
                          ? 'Creating securely…'
                          : 'Create private invitation',
                    ),
                  ),
                ),
              ] else ...[
                Center(
                  child: Semantics(
                    label: 'QR code for the private Braid invitation',
                    image: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: invite.joinUrl,
                        version: QrVersions.auto,
                        size: 210,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF4B2A6B),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF4B2A6B),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(
                  invite.joinUrl,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Expires ${DateFormat('MMM d, yyyy · h:mm a').format(invite.expiresAt)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyInvite,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _shareInvite,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.gradientEnd,
                        ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _invite = null;
                    _errorMessage = null;
                  }),
                  child: const Text('Create another invitation'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
