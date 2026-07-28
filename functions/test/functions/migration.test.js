const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  deriveGroupMigration,
  deriveInsightMigration,
  deriveLifecycle,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
} = require("../../lib/migration");

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
    assert.deepEqual(deriveInsightMigration({}, timestamp), {
      schemaVersion: 2,
      audience: "contacts",
      status: "active",
      updatedAt: timestamp,
    });
  });
});
