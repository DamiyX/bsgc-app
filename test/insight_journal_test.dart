import 'dart:async';

import 'package:bsgc_app/models/insight_model.dart';
import 'package:bsgc_app/models/note_model.dart';
import 'package:bsgc_app/screens/my_insights_screen.dart';
import 'package:bsgc_app/screens/profile_screen.dart';
import 'package:bsgc_app/screens/view_insight_screen.dart';
import 'package:bsgc_app/screens/view_note_screen.dart';
import 'package:bsgc_app/services/insight_service.dart';
import 'package:bsgc_app/services/note_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Insight viewer selection and seen state', () {
    test('My Insights viewer targets the tapped item by ID', () {
      final insights = [
        _insight(id: 'first', body: 'First body'),
        _insight(id: 'selected', body: 'Selected body'),
        _insight(id: 'last', body: 'Last body'),
      ];

      final viewer = buildSelectedInsightViewer(
        insights,
        insights[1],
        seenInsightIds: const {'first'},
      );

      expect(viewer.initialInsightId, 'selected');
      expect(
        resolveInitialInsightIndex(
          viewer.userInsightsGroups.single,
          initialInsightId: viewer.initialInsightId,
          seenInsightIds: viewer.seenInsightIds,
        ),
        1,
      );
    });

    test('first-unseen selection uses per-user state, not legacy seenBy', () {
      final insights = [
        _insight(id: 'legacy-seen', seenBy: const ['current-user']),
        _insight(id: 'state-seen'),
      ];

      expect(
        resolveInitialInsightIndex(
          insights,
          seenInsightIds: const {'state-seen'},
        ),
        0,
      );
      expect(
        resolveInitialInsightIndex(
          insights,
          seenInsightIds: const {'legacy-seen'},
        ),
        1,
      );
    });

    testWidgets(
      'a prebuilt adjacent Insight is marked seen only after it is visible',
      (tester) async {
        final markedInsightIds = <String>[];

        Widget observer({required String insightId, required bool isVisible}) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: InsightSeenObserver(
              insightId: insightId,
              isVisible: isVisible,
              onSeen: markedInsightIds.add,
            ),
          );
        }

        await tester.pumpWidget(
          observer(insightId: 'adjacent', isVisible: false),
        );
        expect(markedInsightIds, isEmpty);

        await tester.pumpWidget(
          observer(insightId: 'adjacent', isVisible: true),
        );
        expect(markedInsightIds, ['adjacent']);

        await tester.pumpWidget(
          observer(insightId: 'adjacent', isVisible: true),
        );
        expect(markedInsightIds, ['adjacent']);

        await tester.pumpWidget(
          observer(insightId: 'next-insight', isVisible: true),
        );
        expect(markedInsightIds, ['adjacent', 'next-insight']);
      },
    );

    testWidgets(
      'MyInsightsScreen renders reflections and builds viewer with seen state',
      (tester) async {
        final insights = [
          _insight(id: 'insight-1', body: 'First body'),
          _insight(id: 'insight-2', body: 'Second body'),
        ];
        final fakeSource = _FakeJournalInsightsDataSource(
          insights: insights,
          seenIds: {'insight-1'},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MyInsightsScreen(
              dataSource: fakeSource,
              currentUserId: 'author',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('insight-1'), findsOneWidget);
        expect(find.text('insight-2'), findsOneWidget);

        final viewer = buildSelectedInsightViewer(
          insights,
          insights[1],
          seenInsightIds: fakeSource.seenIds,
        );
        expect(viewer.initialInsightId, 'insight-2');
        expect(viewer.seenInsightIds, contains('insight-1'));
        expect(
          resolveInitialInsightIndex(
            viewer.userInsightsGroups.single,
            initialInsightId: viewer.initialInsightId,
            seenInsightIds: viewer.seenInsightIds,
          ),
          1,
        );
      },
    );

    testWidgets(
      'tapping a reflection row opens viewer targeting selected insight and seen state',
      (tester) async {
        final insights = [
          _insight(id: 'insight-1', body: 'First body'),
          _insight(id: 'insight-2', body: 'Second body'),
        ];
        final fakeSource = _FakeJournalInsightsDataSource(
          insights: insights,
          seenIds: {'insight-1'},
        );
        InsightModel? openedInsight;
        Set<String>? openedSeenIds;

        await tester.pumpWidget(
          MaterialApp(
            home: MyInsightsScreen(
              dataSource: fakeSource,
              currentUserId: 'author',
              viewerBuilder: (
                insightsList,
                selectedInsight, {
                seenInsightIds = const {},
              }) {
                openedInsight = selectedInsight;
                openedSeenIds = seenInsightIds;
                return Scaffold(
                  body: Text('Viewer for ${selectedInsight.id}'),
                );
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('insight-2'));
        await tester.pumpAndSettle();

        expect(openedInsight?.id, 'insight-2');
        expect(openedSeenIds, contains('insight-1'));
        expect(find.text('Viewer for insight-2'), findsOneWidget);
      },
    );
  });

  group('Saved Insight bookmark contract', () {
    test('only unavailable source failures remove an expiring bookmark', () {
      expect(
        shouldRemoveUnavailableSavedInsight(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        isTrue,
      );
      expect(
        shouldRemoveUnavailableSavedInsight(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
        ),
        isTrue,
      );
      expect(
        shouldRemoveUnavailableSavedInsight(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
    });

    test('privacy and saved-item copy describe implemented behavior', () {
      expect(myInsightsPrivacyNotice, isNot(contains('end-to-end')));
      expect(myInsightsPrivacyNotice, isNot(contains('disappear')));
      expect(savedInsightsRetentionNotice, contains('while they are active'));
      expect(savedInsightsRetentionNotice, contains('removed'));
    });
  });

  group('Journal draft validation', () {
    test('matches the create and Firestore limits', () {
      expect(validateNoteTitle('  '), isNotNull);
      expect(validateNoteTitle('a' * noteTitleMaxLength), isNull);
      expect(validateNoteTitle('a' * (noteTitleMaxLength + 1)), isNotNull);
      expect(validateNoteBody('\n\t'), isNotNull);
      expect(validateNoteBody('a' * noteBodyMaxLength), isNull);
      expect(validateNoteBody('a' * (noteBodyMaxLength + 1)), isNotNull);
    });
  });

  group('View Note save', () {
    testWidgets('rejects an empty body without leaving edit mode', (
      tester,
    ) async {
      final writer = _FakeNoteWriter();
      await tester.pumpWidget(
        MaterialApp(
          home: ViewNoteScreen(note: _note(), noteWriter: writer),
        ),
      );

      await tester.tap(find.byTooltip('Edit note'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('note-body-field')), '');
      await tester.tap(find.byTooltip('Save note'));
      await tester.pump();

      expect(find.text('Write something to save.'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-body-field')), findsOneWidget);
      expect(writer.savedNotes, isEmpty);
    });

    testWidgets(
      'awaits persistence, blocks repeats, and preserves a failed draft',
      (tester) async {
        final saveCompleter = Completer<void>();
        final writer = _FakeNoteWriter(onSave: (_) => saveCompleter.future);
        await tester.pumpWidget(
          MaterialApp(
            home: ViewNoteScreen(note: _note(), noteWriter: writer),
          ),
        );

        await tester.tap(find.byTooltip('Edit note'));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('note-body-field')),
          'Draft that must survive',
        );
        await tester.tap(find.byTooltip('Save note'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(writer.savedNotes, hasLength(1));

        saveCompleter.completeError(Exception('network down'));
        await tester.pumpAndSettle();

        expect(writer.savedNotes, hasLength(1));
        expect(find.text('Draft that must survive'), findsOneWidget);
        expect(
          find.text(
            "Couldn't save this note. Your changes are still here. Try again.",
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('note-body-field')), findsOneWidget);
      },
    );

    testWidgets('reports success only after persistence completes', (
      tester,
    ) async {
      final saveCompleter = Completer<void>();
      final writer = _FakeNoteWriter(onSave: (_) => saveCompleter.future);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewNoteScreen(note: _note(), noteWriter: writer),
        ),
      );

      await tester.tap(find.byTooltip('Edit note'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('note-body-field')),
        'Persisted body',
      );
      await tester.tap(find.byTooltip('Save note'));
      await tester.pump();

      expect(find.text('Note saved.'), findsNothing);
      saveCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.text('Note saved.'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-body-field')), findsNothing);
      expect(find.text('Persisted body', findRichText: true), findsOneWidget);
      expect(writer.savedNotes.single.body, 'Persisted body');
    });

    testWidgets(
      'canceling edit mode reverts changes after discard confirmation',
      (tester) async {
        final writer = _FakeNoteWriter();
        await tester.pumpWidget(
          MaterialApp(
            home: ViewNoteScreen(note: _note(), noteWriter: writer),
          ),
        );

        await tester.tap(find.byTooltip('Edit note'));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('note-body-field')),
          'Draft that will be cancelled',
        );
        await tester.tap(find.byTooltip('Cancel editing'));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('note-body-field')), findsNothing);
        expect(find.text('Original body', findRichText: true), findsOneWidget);
        expect(writer.savedNotes, isEmpty);
      },
    );

    testWidgets(
      'canceling edit mode without unsaved changes exits immediately',
      (tester) async {
        final writer = _FakeNoteWriter();
        await tester.pumpWidget(
          MaterialApp(
            home: ViewNoteScreen(note: _note(), noteWriter: writer),
          ),
        );

        await tester.tap(find.byTooltip('Edit note'));
        await tester.pump();
        await tester.tap(find.byTooltip('Cancel editing'));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byKey(const ValueKey('note-body-field')), findsNothing);
        expect(find.text('Original body', findRichText: true), findsOneWidget);
      },
    );
  });
}

class _FakeNoteWriter implements NoteWriter {
  _FakeNoteWriter({this.onSave});

  final Future<void> Function(NoteModel note)? onSave;
  final List<NoteModel> savedNotes = [];

  @override
  Future<void> saveNote(NoteModel note) {
    savedNotes.add(note);
    return onSave?.call(note) ?? Future.value();
  }
}

InsightModel _insight({
  required String id,
  String body = 'Body',
  List<String> seenBy = const [],
}) {
  final createdAt = DateTime(2026, 7, 29);
  return InsightModel(
    id: id,
    authorUid: 'author',
    authorName: 'Author',
    title: id,
    body: body,
    themeId: 'theme_0',
    seenBy: seenBy,
    createdAt: createdAt,
    updatedAt: createdAt,
    expiresAt: createdAt.add(const Duration(days: 3)),
  );
}

NoteModel _note() {
  final createdAt = DateTime(2026, 7, 29);
  return NoteModel(
    id: 'note-1',
    authorUid: 'current-user',
    title: 'Original title',
    body: 'Original body',
    themeId: 'theme_0',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

class _FakeJournalInsightsDataSource implements MyInsightsDataSource {
  _FakeJournalInsightsDataSource({
    required this.insights,
    this.seenIds = const {},
  });

  final List<InsightModel> insights;
  final Set<String> seenIds;

  @override
  Future<void> deleteInsight(String insightId) async {}

  @override
  Stream<List<InsightModel>> getActiveInsightsForUser(String userId) {
    return Stream.value(insights);
  }

  @override
  Stream<Set<String>> getSeenInsightIds() {
    return Stream.value(seenIds);
  }
}
