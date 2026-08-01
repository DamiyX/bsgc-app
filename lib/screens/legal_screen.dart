import 'package:flutter/material.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    final sections = privacy ? _privacySections : _termsSections;
    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? 'Privacy notice' : 'Community terms'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            privacy ? 'Braid Privacy Notice' : 'Braid Community Terms',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Repository draft • Updated July 28, 2026',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            privacy
                ? 'This notice explains the data contracts implemented in the Braid MVP. A verified operator contact and canonical hosted copy must be added before external beta.'
                : 'These terms describe the behavior supported by Braid’s current safety and moderation controls. A verified operator identity and jurisdiction-specific review must be completed before external beta.',
            style: const TextStyle(height: 1.5),
          ),
          for (final section in sections) ...[
            const SizedBox(height: 22),
            Text(
              section.$1,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(section.$2, style: const TextStyle(height: 1.55)),
          ],
        ],
      ),
    );
  }

  static const _privacySections = <(String, String)>[
    (
      'Data Braid uses',
      'Braid stores a public display name, optional profile photo and bio; private sign-in identifiers; device notification tokens; study-group membership and progress; messages, reflections, comments, reactions, reports, blocks, and invite-created connections. The current MVP does not read or upload your phone book.',
    ),
    (
      'Why it is used',
      'The data is used to authenticate you, provide private journaling and group study, deliver audience-scoped Insights and notifications, enforce capacity and safety controls, prevent abuse, and diagnose crashes. Braid does not use message or reflection content for advertising.',
    ),
    (
      'Who can see content',
      'Journal entries are account-private. Group content is limited to current group members. Contacts Insights are limited to accepted Braid connections while active. Public identity fields can be read only where the app already knows a specific account ID; the global user directory cannot be listed by clients.',
    ),
    (
      'Storage and offline data',
      'The app can keep previously authorized media in a bounded, '
          'account-scoped cache. Firestore also uses local persistence so '
          'previously loaded study data can remain available during warm '
          'offline use. Drafts and failed media uploads are stored locally per '
          'account. Sign-out clears that account’s drafts, outbox, voice/image '
          'caches, and navigation state; a complete Firestore-cache purge is '
          'not currently guaranteed while active listeners exist.',
    ),
    (
      'Notifications',
      'Each installation has its own private notification token. You can disable notifications by category and hide content previews on the lock screen. Invalid tokens are removed automatically.',
    ),
    (
      'Deletion and safety',
      'You can request account deletion from Settings after recent '
          'authentication. Owners must transfer shared groups first. Braid '
          'processes deletion as a resumable background job and removes managed '
          'server media before discarding its cleanup references. Removing access '
          'cannot erase copies another recipient already downloaded. Safety '
          'reports are anonymized or retained for moderation and abuse prevention '
          'according to the operator’s final retention schedule.',
    ),
    (
      'Before external beta',
      'The product operator must publish a verified contact, retention periods, subprocessors, lawful bases, regional rights, child-safety position, and a canonical hosted notice before inviting external testers.',
    ),
  ];

  static const _termsSections = <(String, String)>[
    (
      'Use Braid with care',
      'Braid is for Bible study, reflection, fellowship, and prayer. Do not use it to harass, threaten, exploit, impersonate, spam, expose private information, or distribute unlawful or unsafe material.',
    ),
    (
      'Your content and audience',
      'You remain responsible for content you submit. Check the audience label before sharing. Do not share another person’s private story, prayer request, image, or recording without permission.',
    ),
    (
      'Safety controls',
      'Members can hide, block, and report content or accounts. Braid may restrict or remove content or access when needed for safety, legal compliance, or service integrity. Report tools must not be abused.',
    ),
    (
      'Study guidance',
      'Braid supports fellowship but does not replace professional medical, mental-health, legal, emergency, or safeguarding services. Scripture text availability and attribution are stated in the app; translations are not silently substituted.',
    ),
    (
      'Account responsibility',
      'Keep your sign-in account secure. Group owners are responsible for invitations and role changes. Invite links should be shared only with intended participants and can expire, be revoked, or reach a use limit.',
    ),
    (
      'Service changes',
      'This MVP can change as contracts are validated. Material policy changes must be communicated before they take effect. External beta must not begin until the operator identity, contact, jurisdiction, and final terms are published.',
    ),
  ];
}
