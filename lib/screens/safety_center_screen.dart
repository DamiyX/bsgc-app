import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/safety_service.dart';

class SafetyCenterScreen extends StatelessWidget {
  const SafetyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final safety = SafetyService();
    return Scaffold(
      appBar: AppBar(title: const Text('Safety controls')),
      body: StreamBuilder<List<String>>(
        stream: safety.blockedUserIds(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Blocked accounts could not be loaded.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final blockedIds = snapshot.data!;
          if (blockedIds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You have not blocked anyone. You can report or block a '
                  'member from their group profile menu.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: blockedIds.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final uid = blockedIds[index];
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users_public')
                    .doc(uid)
                    .get(),
                builder: (context, profileSnapshot) {
                  final data = profileSnapshot.data?.data();
                  final name = data?['displayName']?.toString() ?? 'Account';
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                      ),
                    ),
                    title: Text(name),
                    subtitle: const Text('Blocked'),
                    trailing: TextButton(
                      onPressed: () => safety.unblockUser(uid),
                      child: const Text('Unblock'),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
