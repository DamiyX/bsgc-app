import 'package:bsgc_app/models/message_model.dart';
import 'package:bsgc_app/models/insight_model.dart';
import 'package:bsgc_app/screens/foyer_screen.dart';
import 'package:bsgc_app/services/deep_link_service.dart';
import 'package:bsgc_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('canonical invite links reject unsafe hosts and malformed tokens', () {
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN1234';
    expect(
      DeepLinkService.inviteTokenFromUri(
        Uri.parse('https://braidapp.com/join/$token'),
      ),
      token,
    );
    expect(
      DeepLinkService.inviteTokenFromUri(
        Uri.parse('https://evil.example/join/$token'),
      ),
      isNull,
    );
    expect(
      DeepLinkService.inviteTokenFromUri(
        Uri.parse('http://braidapp.com/join/$token'),
      ),
      isNull,
    );
    expect(
      DeepLinkService.inviteTokenFromUri(
        Uri.parse('https://braidapp.com/join/short'),
      ),
      isNull,
    );
  });

  test('message parts retain safe media metadata', () {
    final part = MessagePart.fromMap({
      'type': 'voice',
      'content': 'https://storage.example/voice.m4a',
      'durationSeconds': 42,
    });
    expect(part.type, MessageType.voice);
    expect(part.durationSeconds, 42);
    expect(part.toMap(), {
      'type': 'voice',
      'content': 'https://storage.example/voice.m4a',
      'durationSeconds': 42,
    });
  });

  test('voice message captions round-trip as an optional text equivalent', () {
    final part = MessagePart.fromMap({
      'type': 'voice',
      'content': 'groups/g/messages/m/voice.m4a',
      'durationSeconds': 42,
      'caption': 'A short summary',
    });
    expect(part.caption, 'A short summary');
    expect(part.toMap()['caption'], 'A short summary');
  });

  test(
    'feed snapshots rebuild complete reflections without a dependent read',
    () {
      final created = Timestamp.fromDate(DateTime(2026, 1, 1));
      final insight = InsightModel.fromMap('snapshot-id', {
        'schemaVersion': 2,
        'authorUid': 'author',
        'authorName': 'Author',
        'title': 'Snapshot title',
        'body': 'Snapshot body',
        'themeId': 'theme_0',
        'audience': 'contacts',
        'status': 'active',
        'createdAt': created,
        'updatedAt': created,
        'expiresAt': Timestamp.fromDate(DateTime(2026, 1, 4)),
      });

      expect(insight.id, 'snapshot-id');
      expect(insight.body, 'Snapshot body');
      expect(insight.expiresAt, DateTime(2026, 1, 4));
    },
  );

  testWidgets('sign-in screen remains usable on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: appTheme, home: const FoyerScreen()),
    );
    await tester.pump();

    expect(find.text('Braid'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('light and dark themes expose the Braid semantic colors', () {
    expect(appTheme.extension<BraidSemanticColors>(), isNotNull);
    expect(darkAppTheme.extension<BraidSemanticColors>(), isNotNull);
  });
}
