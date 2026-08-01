const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  ABUSE_POLICIES,
  evaluateRateLimit,
  normalizeGroupMessageInput,
  reportTargetPath,
} = require("../../lib/abuse_controls");

describe("abuse controls", () => {
  test("rate buckets reset, throttle bursts, and cap the window", () => {
    const policy = { windowMs: 60_000, limit: 2, minIntervalMs: 1_000 };
    const first = evaluateRateLimit({}, 10_000, policy);
    assert.equal(first.allowed, true);
    assert.equal(first.next.count, 1);
    const throttled = evaluateRateLimit(first.next, 10_500, policy);
    assert.equal(throttled.reason, "min_interval");
    assert.equal(throttled.retryAfterMillis, 11_000);
    const second = evaluateRateLimit(first.next, 11_000, policy);
    assert.equal(second.allowed, true);
    const capped = evaluateRateLimit(second.next, 12_000, policy);
    assert.equal(capped.reason, "window_limit");
    assert.equal(capped.retryAfterMillis, 70_000);
    assert.equal(
      evaluateRateLimit(second.next, 80_000, policy).next.count,
      1,
    );
  });

  test("defines server policies for every required abuse-prone action", () => {
    for (const action of [
      "create_group",
      "create_group_invite",
      "redeem_group_invite",
      "send_group_message",
      "edit_group_message",
      "send_group_attachment",
      "create_insight_comment",
      "set_reaction",
      "submit_report",
      "publish_insight",
      "insight_fanout",
    ]) {
      assert.ok(ABUSE_POLICIES[action], `${action} policy missing`);
    }
  });

  test("normalizes bounded path-owned messages and rejects forged media", () => {
    const input = normalizeGroupMessageInput({
      groupId: "group-a",
      messageId: "message-a",
      space: "discussion",
      clientMessageId: "client-a",
      parts: [
        { type: "text", content: "Hello" },
        {
          type: "image",
          content: "groups/group-a/messages/message-a/image.jpg",
          assetId: Buffer.from(
            "groups/group-a/messages/message-a/image.jpg",
          ).toString("base64url"),
          sizeBytes: 8,
        },
      ],
    });
    assert.equal(input.parts.length, 2);
    assert.equal(input.attachmentCount, 1);
    assert.throws(() => normalizeGroupMessageInput({
      ...input,
      parts: [{
        type: "image",
        content: "https://tracker.example/image.jpg",
        assetId: "forged",
      }],
    }));
  });

  test("accepts a legitimate four-part message contract", () => {
    const message = normalizeGroupMessageInput({
      groupId: "group-a",
      messageId: "message-four",
      parts: [1, 2, 3, 4].map((number) => ({
        type: "text",
        content: `Part ${number}`,
      })),
    });
    assert.equal(message.parts.length, 4);
    assert.equal(message.attachmentCount, 0);
  });

  test("maps report types only to canonical target paths", () => {
    assert.equal(
      reportTargetPath({ targetType: "insight", targetId: "i1" }),
      "insights/i1",
    );
    assert.equal(
      reportTargetPath({
        targetType: "message",
        targetId: "m1",
        groupId: "g1",
      }),
      "groups/g1/messages/m1",
    );
    assert.equal(
      reportTargetPath({
        targetType: "comment",
        targetId: "c1",
        insightId: "i1",
      }),
      "insights/i1/comments/c1",
    );
    assert.throws(() => reportTargetPath({
      targetType: "message",
      targetId: "m1",
    }));
  });
});
