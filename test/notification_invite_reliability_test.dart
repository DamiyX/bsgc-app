import 'package:bsgc_app/services/deep_link_service.dart';
import 'package:bsgc_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('notification destination contract', () {
    test('round-trips the exact group message and space', () {
      const destination = NotificationDestination(
        type: 'group_message',
        groupId: 'group-1',
        messageId: 'message-9',
        space: 'reflection',
      );

      final restored = NotificationDestination.fromPayload(
        destination.toPayload(),
      );

      expect(restored, isNotNull);
      expect(restored!.type, 'group_message');
      expect(restored.groupId, 'group-1');
      expect(restored.messageId, 'message-9');
      expect(restored.space, 'reflection');
      expect(restored.isValid, isTrue);
    });

    test('rejects an incomplete message destination', () {
      const destination = NotificationDestination(
        type: 'group_message',
        groupId: 'group-1',
      );

      expect(destination.isValid, isFalse);
    });

    test(
      'keeps a destination until that exact destination completes',
      () async {
        final persistence = _MemoryDestinationPersistence();
        final store = NotificationDestinationStore(persistence: persistence);
        const destination = NotificationDestination(
          type: 'group_message',
          groupId: 'group-1',
          messageId: 'message-9',
          space: 'prayer',
        );
        const otherDestination = NotificationDestination(
          type: 'group_message',
          groupId: 'group-2',
          messageId: 'message-10',
          space: 'discussion',
        );

        await store.setPending(destination);
        await store.complete(otherDestination);
        expect(store.value, same(destination));
        expect(persistence.payload, isNotNull);

        await store.complete(destination);
        expect(store.value, isNull);
        expect(persistence.payload, isNull);
      },
    );

    test('restores a pending destination after process recreation', () async {
      final persistence = _MemoryDestinationPersistence();
      const destination = NotificationDestination(
        type: 'insight',
        insightId: 'insight-3',
      );
      persistence.payload = destination.toPayload();

      final store = NotificationDestinationStore(persistence: persistence);
      await store.restore();

      expect(store.value?.insightId, 'insight-3');
    });
  });

  group('notification permission truth', () {
    test('a denied OS permission cannot leave the app preference enabled', () {
      final decision = resolveNotificationPreference(
        requestedEnabled: true,
        permission: DeviceNotificationPermission.denied,
      );

      expect(decision.enabled, isFalse);
      expect(decision.shouldOpenSystemSettings, isTrue);
    });

    test('authorized and provisional permissions can enable notifications', () {
      for (final permission in [
        DeviceNotificationPermission.authorized,
        DeviceNotificationPermission.provisional,
      ]) {
        final decision = resolveNotificationPreference(
          requestedEnabled: true,
          permission: permission,
        );
        expect(decision.enabled, isTrue);
        expect(decision.shouldOpenSystemSettings, isFalse);
      }
    });
  });

  group('invite failure disposition', () {
    test('terminal invite errors are discarded instead of retried forever', () {
      for (final code in [
        'not-found',
        'deadline-exceeded',
        'failed-precondition',
        'resource-exhausted',
        'permission-denied',
      ]) {
        expect(
          classifyInviteFailure(code),
          InviteFailureDisposition.terminal,
          reason: code,
        );
      }
    });

    test('network and backend failures remain retryable', () {
      for (final code in ['unavailable', 'internal', 'cancelled', 'unknown']) {
        expect(
          classifyInviteFailure(code),
          InviteFailureDisposition.retryable,
          reason: code,
        );
      }
    });
  });
}

class _MemoryDestinationPersistence
    implements NotificationDestinationPersistence {
  String? payload;

  @override
  Future<void> clear() async {
    payload = null;
  }

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String value) async {
    payload = value;
  }
}
