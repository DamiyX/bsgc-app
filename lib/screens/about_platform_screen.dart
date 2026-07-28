import 'package:flutter/material.dart';

class AboutPlatformScreen extends StatelessWidget {
  const AboutPlatformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Braid')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
        children: [
          Center(
            child: Semantics(
              image: true,
              label: 'Braid app mark',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/icon2.png',
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                  cacheWidth: 276,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Fellowship shaped around reflection',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Braid helps people notice what they are learning in Scripture, '
            'keep private reflections, and grow through intentional small-group '
            'conversation and prayer.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 28),
          const _ValueCard(
            icon: Icons.edit_note_rounded,
            title: 'Reflect before you broadcast',
            body:
                'A thought can begin privately in Journal. Sharing to a group or to accepted study contacts is always a deliberate audience choice.',
          ),
          const _ValueCard(
            icon: Icons.groups_2_outlined,
            title: 'Small circles, clear purpose',
            body:
                'Each group has a plan, a lifecycle, and dedicated places for reflections, discussion, and prayer—not an endless general-purpose chat.',
          ),
          const _ValueCard(
            icon: Icons.favorite_border_rounded,
            title: 'Healthy engagement',
            body:
                'Braid values substantive questions, completed study steps, and trusted invitations. It avoids popularity-ranked feeds and public follower status.',
          ),
          const _ValueCard(
            icon: Icons.shield_outlined,
            title: 'Privacy by design',
            body:
                'The app separates public identity, private account data, device tokens, and personal state. Phone-book discovery is not part of the current MVP.',
          ),
          const SizedBox(height: 18),
          Text(
            '“As iron sharpens iron, so one person sharpens another.”',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Proverbs 27:17',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _ValueCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(body, style: const TextStyle(height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
