import 'package:flutter/material.dart';

import 'main_hall_screen.dart';

/// Legacy route retained temporarily so old navigation state can recover.
///
/// Contact matching was removed because it exposed the global user directory
/// and relied on ambiguous phone-number suffix comparisons.
@Deprecated('Use secure group invite links instead.')
class InviterSelectionScreen extends StatelessWidget {
  const InviterSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect with a group')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, size: 52),
                  const SizedBox(height: 20),
                  Text(
                    'Join with a private invite',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ask a group owner to share a Braid invite link or QR code. '
                    'Braid no longer uploads or matches your phone contacts.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const MainHallScreen(),
                        ),
                        (route) => false,
                      );
                    },
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
