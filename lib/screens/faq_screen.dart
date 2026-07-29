import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _sections = <String, List<(String, String)>>{
    'Getting started': [
      (
        'What is Braid?',
        'Braid is a focused space for personal Bible reflection and small-group study. Today shows your next step, Groups holds each study plan, Journal keeps private reflections, and Me contains your profile and controls.',
      ),
      (
        'How do I join a group?',
        'Open a trusted Braid invite link or scan its QR code. The invite is expiring and may be revoked or reach its use limit. You will review the app and sign in before joining.',
      ),
      (
        'Why are groups limited to 12 people?',
        'The current MVP is designed for small circles where each person can be heard. Capacity is enforced by the server so simultaneous joins cannot exceed the limit.',
      ),
    ],
    'Study groups': [
      (
        'What are Plan, Reflections, Discussion, and Prayer?',
        'Plan tracks the study and your personal progress. Reflections is for what stood out. Discussion is for questions and conversation. Prayer keeps requests and prayers easy to revisit.',
      ),
      (
        'What happens before a study starts?',
        'A scheduled group can be reviewed, but posting and progress changes wait until its start date. Braid updates the room when the lifecycle changes.',
      ),
      (
        'What happens when a study ends?',
        'The group becomes read-only and shows a recap. Members can revisit the plan, reflections, discussion, and prayer. The owner may archive it later.',
      ),
      (
        'Who can invite or remove members?',
        'Only the group owner can create group invites, remove members, extend the study, or transfer ownership. A member can leave at any time; an owner must transfer ownership before leaving.',
      ),
    ],
    'Reflections and Insights': [
      (
        'Are Journal reflections private?',
        'Yes. Journal reflections are stored in your private account area. They are not shared unless you deliberately create a separate group reflection or contacts Insight.',
      ),
      (
        'Who can see an Insight?',
        'An Insight marked for study contacts is available only to your accepted Braid connections while it is active. A person commenting on one Insight does not gain access to anyone else’s Insights.',
      ),
      (
        'Does Braid rank people by likes or followers?',
        'No. Reactions help someone acknowledge a reflection, but Braid does not use popularity rankings or public follower-style status.',
      ),
    ],
    'Offline and data': [
      (
        'What works without internet?',
        'Previously loaded groups, messages, avatars, covers, KJV, and WEB can remain available from local caches. New text writes use Firestore’s offline queue. Media that cannot upload stays in Braid’s local outbox with a clear Retry option.',
      ),
      (
        'Why might an image show initials or a placeholder?',
        'If an image has never been downloaded or its file is unavailable, Braid shows a deterministic local fallback instead of a blank or random remote image.',
      ),
      (
        'Does Braid upload my contacts?',
        'No. The MVP does not read or upload your phone book. Connections are created intentionally through accepted invitations.',
      ),
      (
        'Which Bible translations are included?',
        'KJV and WEB are bundled for offline use. Braid does not claim or silently substitute translations that are not included and licensed.',
      ),
    ],
    'Safety and account': [
      (
        'How do I report or block someone?',
        'Use the message, Insight, or group-member menu, or open Me → Safety center. Reports go to Braid’s moderation queue; blocks are private to your account.',
      ),
      (
        'Can I delete my account?',
        'Yes. Settings → Account → Delete account starts a recent-authentication-protected deletion. If you own a shared group, transfer ownership first so other members are not stranded.',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help and frequently asked questions')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final section in _sections.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
              child: Text(
                section.key,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final item in section.value)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  minTileHeight: 56,
                  title: Text(
                    item.$1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$2, style: const TextStyle(height: 1.5)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
