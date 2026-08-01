const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  canonicalInvitePath,
  deriveGroupMigration,
  deriveInviteMigration,
  deriveInsightMigration,
  deriveLifecycle,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
  validateCanonicalDocument,
  validateManagedMessageAsset,
} = require("../../lib/migration");
const fixtures = require("../fixtures/migration-legacy");

const timestamp = {
  toMillis: () => 1_000_000,
};

describe("user migration", () => {
  test("separates public identity from private phone and token fields", () => {
    const result = deriveUserDocuments(
      "alice",
      {
        displayName: " Alice ",
        photoURL: "https://example.test/alice.jpg",
        phoneNumbers: ["+2348000000000", "+2348000000000"],
        fcmToken: "t".repeat(40),
        referredBy: "inviter",
        deletionState: "blocked",
        notificationPreferences: { enabled: false },
        storagePreferences: { wifiOnly: true },
      },
      timestamp,
    );

    assert.equal(result.public.uid, "alice");
    assert.equal(result.public.displayName, "Alice");
    assert.equal(result.public.phoneNumbers, undefined);
    assert.deepEqual(result.private.phoneNumbers, ["+2348000000000"]);
    assert.equal(result.private.phoneVerified, false);
    assert.equal(result.private.contactDiscoveryConsent, false);
    assert.equal(result.private.connectionCount, 0);
    assert.equal(result.private.deletionState, "blocked");
    assert.deepEqual(result.private.notificationPreferences, {
      enabled: false,
    });
    assert.deepEqual(result.private.storagePreferences, { wifiOnly: true });
    assert.equal(result.legacyFcmToken, "t".repeat(40));
  });
});

describe("nested user data migration", () => {
  test("adds a bounded v2 contract to legacy notes", () => {
    const note = deriveNoteMigration(
      "alice",
      { title: " Grace ", body: "Remember this", themeColor: "paper" },
      timestamp,
    );
    assert.equal(note.schemaVersion, 2);
    assert.equal(note.authorUid, "alice");
    assert.equal(note.title, "Grace");
    assert.equal(note.themeId, "paper");
  });

  test("preserves legacy note bodies up to the v2 50,000 character limit", () => {
    const body = "a".repeat(50_000);
    const note = deriveNoteMigration(
      "alice",
      { title: "Long study", body },
      timestamp,
    );

    assert.equal(note.body.length, 50_000);
    assert.equal(note.body, body);
  });

  test("quarantines a legacy note that exceeds the v2 body limit", () => {
    const migration = deriveNoteMigration(
      "alice",
      { title: "Oversized study", body: "a".repeat(50_001) },
      timestamp,
    );

    assert.equal(migration.issue.code, "note-body-limit-exceeded");
    assert.equal(migration.body, undefined);
  });

  test("converts saved documents to private pointers", () => {
    assert.deepEqual(
      deriveSavedInsightMigration("insight-a", {}, timestamp),
      { insightId: "insight-a", savedAt: timestamp },
    );
  });
});

describe("message migration", () => {
  test("converts a legacy text message into discussion space", () => {
    const result = deriveMessageMigration(
      "message-a",
      { type: "text", content: "Hello", senderId: "alice" },
      timestamp,
    );
    assert.equal(result.message.schemaVersion, 2);
    assert.equal(result.message.clientMessageId, "message-a");
    assert.equal(result.message.space, "discussion");
    assert.equal(result.message.senderId, "alice");
    assert.equal(result.message.senderName, "Braid member");
    assert.deepEqual(result.message.parts, [
      { type: "text", content: "Hello" },
    ]);
  });

  test("refuses to keep inline voice data in Firestore", () => {
    const result = deriveMessageMigration(
      "voice-a",
      {
        senderId: "alice",
        type: "voice",
        content: "base64-inline-audio",
      },
      timestamp,
    );
    assert.equal(
      result.issue.code,
      "inline-voice-requires-storage-migration",
    );
  });

  test("refuses to keep inline image data in Firestore", () => {
    const result = deriveMessageMigration(
      "image-a",
      {
        senderId: "alice",
        type: "image",
        content: "base64-inline-image",
      },
      timestamp,
    );
    assert.equal(
      result.issue.code,
      "inline-image-requires-storage-migration",
    );
  });

  test("refuses to invent a sender for an anonymous legacy message", () => {
    const result = deriveMessageMigration(
      "anonymous-a",
      { type: "text", content: "Unknown author" },
      timestamp,
    );
    assert.equal(result.issue.code, "missing-message-sender");
  });

  test("preserves a deleted message as a sender-bound tombstone", () => {
    const result = deriveMessageMigration(
      "deleted-a",
      {
        senderId: "alice",
        senderName: "Alice",
        isDeleted: true,
        parts: [],
      },
      timestamp,
    );
    assert.equal(result.message.senderId, "alice");
    assert.equal(result.message.isDeleted, true);
    assert.deepEqual(result.message.parts, []);
  });
});

describe("group migration", () => {
  test("uses the existing implied first-member owner and creates explicit roles", () => {
    const result = deriveGroupMigration(
      "group-a",
      {
        members: ["owner", "member"],
        extensionCount: 9,
      },
      timestamp,
    );

    assert.equal(result.group.ownerId, "owner");
    assert.equal(result.group.extensionCount, 3);
    assert.deepEqual(
      result.members.map(({ uid, role }) => ({ uid, role })),
      [
        { uid: "owner", role: "owner" },
        { uid: "member", role: "member" },
      ],
    );
  });

  test("normalizes all required fields and UID-keyed maps", () => {
    const fixture = fixtures.groups[0];
    const result = deriveGroupMigration(fixture.id, fixture.data, timestamp);

    assert.equal(result.group.name, "Study group");
    assert.equal(result.group.description, "");
    assert.equal(result.group.groupType, "Topic");
    assert.deepEqual(result.group.members, ["owner", "member"]);
    assert.deepEqual(result.group.readingProgress, { owner: 1, member: 0 });
    assert.deepEqual(result.group.userCompletedChapters, {
      owner: [1],
      member: [],
    });
    assert.deepEqual(result.group.unreadCounts, { owner: 0, member: 4 });
    assert.deepEqual(
      validateCanonicalDocument("group", result.group),
      [],
    );
  });

  test("refuses to guess ownership for an empty group", () => {
    const result = deriveGroupMigration(
      "empty",
      { members: [] },
      timestamp,
    );
    assert.equal(result.issue.code, "missing-members");
    assert.equal(result.group, undefined);
  });

  test("derives lifecycle from dates without changing explicit lifecycle", () => {
    assert.equal(deriveLifecycle({ lifecycle: "archived" }, 10), "archived");
    assert.equal(
      deriveLifecycle({ startDate: { toMillis: () => 20 } }, 10),
      "scheduled",
    );
    assert.equal(
      deriveLifecycle({ endDate: { toMillis: () => 5 } }, 10),
      "completed",
    );
  });
});

describe("Insight migration", () => {
  test("makes the intended contacts audience explicit", () => {
    const insight = deriveInsightMigration({
      authorUid: "alice",
      authorName: "Alice",
      body: "Grace",
    }, timestamp, {
      fromMillis: (millis) => ({ toMillis: () => millis }),
    }).insight;
    assert.deepEqual({ ...insight, expiresAt: undefined }, {
      schemaVersion: 2,
      authorUid: "alice",
      authorName: "Alice",
      title: "",
      body: "Grace",
      themeId: "theme_0",
      audience: "contacts",
      status: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
      expiresAt: undefined,
    });
    assert.equal(insight.expiresAt.toMillis(), 260_200_000);
  });

  test("normalizes every required legacy Insight field", () => {
    const result = deriveInsightMigration(
      fixtures.insights[0].data,
      timestamp,
      { fromMillis: (millis) => ({ toMillis: () => millis }) },
    );
    assert.equal(result.insight.authorUid, "legacy-user");
    assert.equal(result.insight.authorName, "Legacy User");
    assert.equal(result.insight.body, "A reflection");
    assert.equal(result.insight.title, "");
    assert.equal(result.insight.themeId, "theme_3");
    assert.deepEqual(result.insight.seenBy, ["viewer"]);
    assert.equal(result.insight.expiresAt.toMillis(), 260_200_000);
    assert.deepEqual(
      validateCanonicalDocument("insight", result.insight),
      [],
    );
  });
});

describe("canonical validation and idempotence", () => {
  test("preserves a Unicode note and quarantines empty bodies", () => {
    const valid = deriveNoteMigration(
      "legacy-user",
      fixtures.notes[0].data,
      timestamp,
    );
    assert.equal(valid.body, fixtures.unicodeNoteBody);
    assert.deepEqual(validateCanonicalDocument("note", valid), []);

    const invalid = deriveNoteMigration(
      "legacy-user",
      fixtures.notes[1].data,
      timestamp,
    );
    assert.equal(invalid.issue.code, "empty-note-body");
  });

  test("keeps only already-managed media and rejects legacy HTTPS media", () => {
    const managed = fixtures.messages[1];
    const result = deriveMessageMigration(
      managed.id,
      managed.data,
      timestamp,
      { groupId: managed.groupId },
    );
    assert.equal(result.message.parts[0].assetId, "managed-asset");
    assert.deepEqual(validateCanonicalDocument("message", result.message), []);
    assert.deepEqual(validateManagedMessageAsset(
      result.message.parts[0],
      {
        assetId: "managed-asset",
        storagePath:
          "groups/legacy-group/messages/legacy-managed-voice/audio.m4a",
        ownerUid: "owner",
        entityType: "message",
        entityId: "legacy-managed-voice",
        groupId: "legacy-group",
        status: "committed",
        sizeBytes: 1024,
        mimeType: "audio/m4a",
      },
      {
        groupId: "legacy-group",
        messageId: "legacy-managed-voice",
        senderId: "owner",
      },
    ), []);

    const external = fixtures.messages[2];
    assert.equal(
      deriveMessageMigration(
        external.id,
        external.data,
        timestamp,
        { groupId: external.groupId },
      ).issue.code,
      "external-media-requires-storage-migration",
    );
  });

  test("canonical output is stable when transformed again", () => {
    const first = deriveGroupMigration(
      "legacy-group",
      fixtures.groups[0].data,
      timestamp,
    );
    const second = deriveGroupMigration(
      "legacy-group",
      first.group,
      timestamp,
    );
    assert.deepEqual(second.group, first.group);
  });
});

describe("invite migration", () => {
  test("uses invites and hashes a legacy raw-token document id", () => {
    const fixture = fixtures.invites[0];
    const result = deriveInviteMigration(
      fixture.id,
      fixture.data,
      timestamp,
    );
    assert.match(result.inviteId, /^[a-f0-9]{64}$/);
    assert.equal(
      canonicalInvitePath(result.inviteId),
      `invites/${result.inviteId}`,
    );
    assert.equal(result.invite.groupId, "legacy-group");
    assert.equal(result.invite.createdBy, "owner");
    assert.equal(result.invite.maxUses, 3);
    assert.equal(result.invite.useCount, 1);
    assert.equal(Object.hasOwn(result.invite, "token"), false);
    assert.deepEqual(validateCanonicalDocument("invite", result.invite), []);
  });
});
