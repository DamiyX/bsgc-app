import 'dart:convert';

import 'package:bsgc_app/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only path-bound managed message media', () {
    const path = 'groups/group-a/messages/message-a/image.jpg';
    final assetId = base64Url.encode(utf8.encode(path)).replaceAll('=', '');
    expect(
      MessagePart(
        type: MessageType.image,
        content: path,
        assetId: assetId,
      ).hasCanonicalManagedIdentity,
      isTrue,
    );
    expect(
      MessagePart(
        type: MessageType.image,
        content: path,
        assetId: 'forged',
      ).hasCanonicalManagedIdentity,
      isFalse,
    );
    expect(
      MessagePart(
        type: MessageType.image,
        content: 'groups/group-a/covers/image.jpg',
        assetId: assetId,
      ).hasCanonicalManagedIdentity,
      isFalse,
    );
  });

  test('classifies legacy HTTPS media as an explicit external link', () {
    final part = MessagePart(
      type: MessageType.voice,
      content: 'https://tracker.example/voice.m4a',
      durationSeconds: 10,
    );
    expect(part.hasCanonicalManagedIdentity, isFalse);
    expect(part.isExternalMediaLink, isTrue);
  });
}
