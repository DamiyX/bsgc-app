import 'dart:async';
import 'dart:io';

import 'package:bsgc_app/models/insight_model.dart';
import 'package:bsgc_app/screens/my_insights_screen.dart';
import 'package:bsgc_app/services/draft_service.dart';
import 'package:bsgc_app/services/insight_action_controller.dart';
import 'package:bsgc_app/services/insight_mutation_contract.dart';
import 'package:bsgc_app/services/insight_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reversible Insight actions', () {
    test('rolls an optimistic toggle back when persistence fails', () async {
      final write = Completer<void>();
      final controller = ReversibleToggleController(initialValue: false);

      final action = controller.toggle((_) => write.future);

      expect(controller.value, isTrue);
      expect(controller.isPending, isTrue);
      expect(await controller.toggle((_) async {}), isFalse);

      write.completeError(Exception('offline'));
      expect(await action, isFalse);
      expect(controller.value, isFalse);
      expect(controller.isPending, isFalse);
      expect(controller.lastError, isNotNull);
    });

    test('keeps the committed value after persistence succeeds', () async {
      final controller = ReversibleToggleController(initialValue: false);

      expect(
        await controller.toggle((next) async {
          expect(next, isTrue);
        }),
        isTrue,
      );

      expect(controller.value, isTrue);
      expect(controller.isPending, isFalse);
      expect(controller.lastError, isNull);
    });

    test(
      'preserves comment text on failure and clears it on success',
      () async {
        final textController = TextEditingController(text: 'Keep this comment');

        expect(
          await persistCommentText(textController, (_) async {
            throw Exception('offline');
          }),
          isFalse,
        );
        expect(textController.text, 'Keep this comment');

        expect(await persistCommentText(textController, (_) async {}), isTrue);
        expect(textController.text, isEmpty);
      },
    );

    test(
      'bounds comment persistence and preserves text after a timeout',
      () async {
        final textController = TextEditingController(text: 'Keep this comment');

        expect(
          await persistCommentText(
            textController,
            (_) => Completer<void>().future,
            timeout: const Duration(milliseconds: 10),
          ),
          isFalse,
        );
        expect(textController.text, 'Keep this comment');
      },
    );

    test(
      'bounds reversible toggles and rolls them back after a timeout',
      () async {
        final controller = ReversibleToggleController(
          initialValue: false,
          timeout: const Duration(milliseconds: 10),
        );

        expect(
          await controller.toggle((_) => Completer<void>().future),
          isFalse,
        );
        expect(controller.value, isFalse);
        expect(controller.isPending, isFalse);
        expect(controller.lastError, isA<TimeoutException>());
      },
    );

    test(
      'shared Insight mutation boundary rejects an unresolved operation',
      () async {
        await expectLater(
          awaitInsightMutation(
            Completer<void>().future,
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(insightMutationTimeout, const Duration(seconds: 8));
      },
    );
  });

  group('comment cursor pages', () {
    test('merges pages chronologically without duplicate cursor overlap', () {
      final older = [
        _comment(id: 'c1', minute: 1),
        _comment(id: 'c2', minute: 2),
      ];
      final newer = [
        _comment(id: 'c2', minute: 2),
        _comment(id: 'c3', minute: 3),
      ];

      final merged = mergeCommentPages(newer, older);

      expect(merged.map((comment) => comment.id), ['c1', 'c2', 'c3']);
    });

    test('keeps replies renderable when their parent is outside the page', () {
      final orphanReply = _comment(
        id: 'reply',
        minute: 3,
        replyToId: 'older-parent',
      );

      expect(commentThreadRoots([orphanReply]), [orphanReply]);

      final parent = _comment(id: 'older-parent', minute: 1);
      expect(commentThreadRoots([parent, orphanReply]), [parent]);
    });

    test('newest page contract uses a bounded stable cursor', () {
      final page = InsightCommentPage(
        comments: [_comment(id: 'newest', minute: 3)],
        hasMore: true,
        cursor: const InsightCommentCursor(
          documentId: 'newest',
          createdAtMicros: 3,
        ),
      );

      expect(page.comments.single.id, 'newest');
      expect(page.hasMore, isTrue);
      expect(page.cursor?.documentId, 'newest');
    });
  });

  group('truthful Insight deletion', () {
    testWidgets('confirms deletion and never offers replacement-record undo', (
      tester,
    ) async {
      final source = _FakeMyInsightsDataSource([_insight()]);
      await tester.pumpWidget(
        MaterialApp(
          home: MyInsightsScreen(
            dataSource: source,
            currentUserId: 'current-user',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete reflection?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(source.deletedIds, ['insight-1']);
      expect(find.text('Reflection deleted'), findsOneWidget);
      expect(find.text('UNDO'), findsNothing);
    });

    testWidgets('reports deletion success only after persistence completes', (
      tester,
    ) async {
      final deletion = Completer<void>();
      final source = _FakeMyInsightsDataSource([
        _insight(),
      ], onDelete: (_) => deletion.future);
      await tester.pumpWidget(
        MaterialApp(
          home: MyInsightsScreen(
            dataSource: source,
            currentUserId: 'current-user',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();

      expect(source.deletedIds, ['insight-1']);
      expect(find.text('Reflection deleted'), findsNothing);

      deletion.complete();
      await tester.pumpAndSettle();

      expect(find.text('Reflection deleted'), findsOneWidget);
    });
  });

  group('account-scoped composer drafts', () {
    late Directory root;
    late DraftService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('braid-draft-test-');
      service = DraftService(
        draftRootProvider: (userId) async {
          return Directory('${root.path}${Platform.pathSeparator}$userId');
        },
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'private and contact drafts restore only for the same account',
      () async {
        const privateDraft = ComposerDraft(
          title: 'Private title',
          body: 'Private reflection',
          audience: ComposerDraftAudience.private,
        );
        const contactDraft = ComposerDraft(
          title: 'Shared title',
          body: 'Shared reflection',
          audience: ComposerDraftAudience.contacts,
        );

        await service.saveComposerDraft(
          userId: 'account-a',
          draft: privateDraft,
        );
        await service.saveComposerDraft(
          userId: 'account-a',
          draft: contactDraft,
        );

        expect(
          await service.loadComposerDraft(
            userId: 'account-a',
            audience: ComposerDraftAudience.private,
          ),
          privateDraft,
        );
        expect(
          await service.loadComposerDraft(
            userId: 'account-a',
            audience: ComposerDraftAudience.contacts,
          ),
          contactDraft,
        );
        expect(
          await service.loadComposerDraft(
            userId: 'account-b',
            audience: ComposerDraftAudience.private,
          ),
          isNull,
        );
      },
    );

    test('empty draft and explicit clear remove the durable record', () async {
      const draft = ComposerDraft(
        title: 'Recover me',
        body: 'Body',
        audience: ComposerDraftAudience.contacts,
      );
      await service.saveComposerDraft(userId: 'account-a', draft: draft);
      await service.clearComposerDraft(
        userId: 'account-a',
        audience: ComposerDraftAudience.contacts,
      );

      expect(
        await service.loadComposerDraft(
          userId: 'account-a',
          audience: ComposerDraftAudience.contacts,
        ),
        isNull,
      );

      await service.saveComposerDraft(
        userId: 'account-a',
        draft: const ComposerDraft(
          title: ' ',
          body: '\n',
          audience: ComposerDraftAudience.contacts,
        ),
      );
      expect(
        await service.loadComposerDraft(
          userId: 'account-a',
          audience: ComposerDraftAudience.contacts,
        ),
        isNull,
      );
    });
  });
}

class _FakeMyInsightsDataSource implements MyInsightsDataSource {
  _FakeMyInsightsDataSource(List<InsightModel> insights, {this.onDelete})
    : _insights = insights;

  final List<InsightModel> _insights;
  final Future<void> Function(String insightId)? onDelete;
  final List<String> deletedIds = [];

  @override
  Future<void> deleteInsight(String insightId) async {
    deletedIds.add(insightId);
    await onDelete?.call(insightId);
  }

  @override
  Stream<List<InsightModel>> getActiveInsightsForUser(String userId) {
    return Stream.value(_insights);
  }
}

InsightModel _insight() {
  final createdAt = DateTime(2026, 7, 29);
  return InsightModel(
    id: 'insight-1',
    authorUid: 'current-user',
    authorName: 'Current User',
    title: 'Insight title',
    body: 'Insight body',
    themeId: 'theme_0',
    createdAt: createdAt,
    updatedAt: createdAt,
    expiresAt: createdAt.add(const Duration(days: 3)),
  );
}

InsightCommentModel _comment({
  required String id,
  required int minute,
  String? replyToId,
}) {
  return InsightCommentModel(
    id: id,
    insightId: 'insight-1',
    authorUid: 'author',
    authorName: 'Author',
    body: id,
    replyToId: replyToId,
    createdAt: DateTime(2026, 7, 29, 12, minute),
  );
}
