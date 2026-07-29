const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  connectionDocument,
  createInviteToken,
  hashInviteToken,
  isInvalidMessagingTokenError,
  messageNotificationData,
  messagePreview,
  normalizeInsightInput,
  normalizeReportInput,
  parseMessageAssetPath,
  requireInteger,
  requireString,
} = require("../../lib/contracts");

describe("callable input contracts", () => {
  test("normalizes bounded strings and rejects invalid values", () => {
    assert.equal(requireString("  Study  ", "name", 80), "Study");
    assert.throws(() => requireString("", "name", 80), RangeError);
    assert.throws(() => requireString(42, "name", 80), TypeError);
    assert.throws(() => requireString("x".repeat(81), "name", 80), RangeError);
  });

  test("requires bounded integers", () => {
    assert.equal(requireInteger(3, "maxUses", { min: 1, max: 12 }), 3);
    assert.throws(
      () => requireInteger(13, "maxUses", { min: 1, max: 12 }),
      RangeError,
    );
    assert.throws(
      () => requireInteger(1.5, "maxUses", { min: 1, max: 12 }),
      RangeError,
    );
  });
});

describe("invite security", () => {
  test("generates high-entropy opaque tokens and stores only deterministic hashes", () => {
    const first = createInviteToken();
    const second = createInviteToken();

    assert.notEqual(first, second);
    assert.ok(first.length >= 40);
    assert.equal(hashInviteToken(first), hashInviteToken(first));
    assert.notEqual(hashInviteToken(first), hashInviteToken(second));
    assert.equal(hashInviteToken(first).length, 64);
  });

  test("builds symmetric accepted-connection records without raw tokens", () => {
    const acceptedAt = { seconds: 1 };
    const record = connectionDocument(
      "invitee",
      "inviter",
      acceptedAt,
      "token-hash",
    );

    assert.deepEqual(record, {
      schemaVersion: 2,
      otherUid: "inviter",
      status: "accepted",
      acceptedAt,
      source: "group_invite",
      sourceInviteId: "token-hash",
    });
  });
});

describe("notification safety", () => {
  test("routes group notifications to the exact message space", () => {
    assert.deepEqual(
      messageNotificationData({
        groupId: "group-a",
        messageId: "message-9",
        space: "prayer",
      }),
      {
        version: "1",
        type: "group_message",
        groupId: "group-a",
        messageId: "message-9",
        space: "prayer",
      },
    );
    assert.throws(
      () => messageNotificationData({
        groupId: "group-a",
        messageId: "message-9",
        space: "plan",
      }),
      RangeError,
    );
  });

  test("creates a bounded single-line preview", () => {
    assert.equal(
      messagePreview([{ type: "text", content: "Hello\nthere" }]),
      "Hello there",
    );
    assert.equal(
      messagePreview([{ type: "text", content: "x".repeat(100) }]).length,
      80,
    );
    assert.equal(messagePreview([{ type: "voice", content: "url" }]), "Voice note");
    assert.equal(messagePreview([{ type: "image", content: "url" }]), "Image");
    assert.equal(messagePreview([]), "Sent a message");
  });

  test("recognizes only token errors that require device cleanup", () => {
    assert.equal(
      isInvalidMessagingTokenError(
        "messaging/registration-token-not-registered",
      ),
      true,
    );
    assert.equal(
      isInvalidMessagingTokenError("messaging/internal-error"),
      false,
    );
  });
});

describe("message media paths", () => {
  test("accepts only the canonical group-message asset path", () => {
    assert.deepEqual(
      parseMessageAssetPath(
        "groups/group-a/messages/message-1/part_0.m4a",
      ),
      {
        groupId: "group-a",
        messageId: "message-1",
        assetId: "part_0.m4a",
      },
    );
    assert.equal(
      parseMessageAssetPath("users/alice/profile/photo.jpg"),
      null,
    );
    assert.equal(
      parseMessageAssetPath("groups/a/messages/b/../../secret"),
      null,
    );
  });
});

describe("community publishing contracts", () => {
  test("normalizes a bounded contacts Insight", () => {
    assert.deepEqual(
      normalizeInsightInput({
        title: "  Grace  ",
        body: "  A reflection. ",
        themeId: "theme_2",
      }),
      {
        title: "Grace",
        body: "A reflection.",
        themeId: "theme_2",
      },
    );
    assert.throws(
      () => normalizeInsightInput({
        title: "Title",
        body: "Body",
        themeId: "custom_css",
      }),
      RangeError,
    );
  });

  test("accepts only supported report targets and reasons", () => {
    assert.deepEqual(
      normalizeReportInput({
        targetType: "message",
        targetId: "message-a",
        groupId: "group-a",
        reason: "harassment",
        details: "  Context  ",
      }),
      {
        targetType: "message",
        targetId: "message-a",
        groupId: "group-a",
        reason: "harassment",
        details: "Context",
      },
    );
    assert.throws(
      () => normalizeReportInput({
        targetType: "database",
        targetId: "x",
        reason: "other",
      }),
      RangeError,
    );
  });
});
