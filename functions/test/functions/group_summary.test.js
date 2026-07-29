const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  groupSummaryFromMessage,
  shouldReconcileGroupSummary,
} = require("../../lib/group_summary");

describe("group last-message summaries", () => {
  test("projects the latest non-deleted message using canonical identity", () => {
    const timestamp = { seconds: 123 };
    assert.deepEqual(
      groupSummaryFromMessage({
        messageId: "message-9",
        message: {
          senderId: "alice",
          senderName: "Spoofed name",
          timestamp,
          parts: [{ type: "text", content: "Grace\nfor today" }],
        },
        canonicalSenderName: "Alice",
        fallbackTimestamp: { seconds: 999 },
      }),
      {
        lastMessageId: "message-9",
        lastMessageTime: timestamp,
        lastMessageText: "Grace for today",
        lastMessageSenderName: "Alice",
        lastMessageSenderId: "alice",
      },
    );
  });

  test("reconciles current or legacy summaries but skips unrelated history", () => {
    assert.equal(
      shouldReconcileGroupSummary({
        lastMessageId: "message-9",
        changedMessageId: "message-9",
      }),
      true,
    );
    assert.equal(
      shouldReconcileGroupSummary({
        lastMessageId: null,
        changedMessageId: "legacy-message",
      }),
      true,
    );
    assert.equal(
      shouldReconcileGroupSummary({
        lastMessageId: "message-10",
        changedMessageId: "message-9",
        latestMessageId: "message-10",
      }),
      false,
    );
    assert.equal(
      shouldReconcileGroupSummary({
        lastMessageId: "message-8",
        changedMessageId: "message-9",
        latestMessageId: "message-9",
      }),
      true,
      "an edit that races the create summary must repair the stale pointer",
    );
    assert.equal(
      shouldReconcileGroupSummary({
        lastMessageId: "deleted-message",
        changedMessageId: "older-deleted-message",
        latestMessageId: null,
      }),
      true,
      "account-deletion batches must clear a summary with no visible message",
    );
  });
});
