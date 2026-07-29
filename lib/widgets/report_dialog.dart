import 'package:flutter/material.dart';

import '../services/safety_service.dart';

Future<bool> showReportDialog(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? groupId,
}) async {
  const reasons = <String, String>{
    'spam': 'Spam or promotion',
    'harassment': 'Harassment or bullying',
    'hate': 'Hate or dehumanizing content',
    'sexual_content': 'Sexual content',
    'violence': 'Violence or threats',
    'self_harm': 'Self-harm concern',
    'misinformation': 'Harmful misinformation',
    'other': 'Something else',
  };
  String selectedReason = 'spam';
  final detailsController = TextEditingController();
  final shouldSubmit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Report to Braid'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                items: reasons.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedReason = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: detailsController,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Additional details (optional)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit report'),
          ),
        ],
      ),
    ),
  );

  if (shouldSubmit != true) {
    detailsController.dispose();
    return false;
  }
  try {
    await SafetyService().report(
      targetType: targetType,
      targetId: targetId,
      groupId: groupId,
      reason: selectedReason,
      details: detailsController.text,
    );
    detailsController.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Report submitted. Thank you for helping keep Braid safe.',
          ),
        ),
      );
    }
    return true;
  } catch (_) {
    detailsController.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report could not be submitted.')),
      );
    }
    return false;
  }
}
