import 'package:bsgc_app/models/group_model.dart';
import 'package:bsgc_app/screens/create_insight_screen.dart';
import 'package:bsgc_app/screens/main_hall_screen.dart';
import 'package:bsgc_app/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime(2026, 1, 1);

  GroupModel group(String id, String lifecycle, {DateTime? endDate}) {
    return GroupModel(
      id: id,
      ownerId: 'owner',
      name: id,
      members: const ['owner'],
      readingProgress: const {},
      pinnedScripture: '',
      createdAt: created,
      lifecycle: lifecycle,
      endDate: endDate,
    );
  }

  test('Today selects an active study, never a scheduled placeholder', () {
    expect(
      selectTodayStudy([
        group('scheduled', 'scheduled'),
        group('archived', 'archived'),
        group('active', 'active'),
      ])?.id,
      'active',
    );
    expect(selectTodayStudy([group('scheduled', 'scheduled')]), isNull);
  });

  test('archived study retrieval filters and sorts only archived records', () {
    final archived = ChatService.sortArchivedGroups([
      group('older', 'archived', endDate: DateTime(2026, 2, 1)),
      group('active', 'active', endDate: DateTime(2026, 4, 1)),
      group('newer', 'archived', endDate: DateTime(2026, 5, 1)),
    ]);

    expect(archived.map((item) => item.id), ['newer', 'older']);
  });

  test('Journal share-copy entry point carries the private text forward', () {
    const composer = CreateInsightScreen(
      initialTitle: 'A private title',
      initialBody: 'A private reflection',
    );

    expect(composer.initialTitle, 'A private title');
    expect(composer.initialBody, 'A private reflection');
  });
}
