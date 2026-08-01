const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  buildModerationAuditRecord,
  moderationCapabilities,
  normalizeModerationDecision,
} = require("../../lib/moderation");

describe("moderation operations", () => {
  test("uses capability-scoped operator roles", () => {
    assert.deepEqual(
      moderationCapabilities({ moderationRole: "support" }),
      ["read_queue"],
    );
    assert.ok(
      moderationCapabilities({ moderationRole: "moderator" })
        .includes("remove_content"),
    );
    assert.ok(
      moderationCapabilities({ moderationRole: "trust_safety_admin" })
        .includes("suspend_account"),
    );
    assert.deepEqual(moderationCapabilities({ moderator: true }), []);
  });

  test("normalizes allowlisted decisions and rejects missing evidence", () => {
    assert.deepEqual(normalizeModerationDecision({
      actionId: "action-a",
      reportId: "report-a",
      action: "remove_content",
      taxonomy: "harassment",
      rationale: "Repeated targeted abuse in the reported message.",
    }), {
      actionId: "action-a",
      reportId: "report-a",
      action: "remove_content",
      taxonomy: "harassment",
      rationale: "Repeated targeted abuse in the reported message.",
    });
    assert.throws(() => normalizeModerationDecision({
      actionId: "action-b",
      reportId: "report-a",
      action: "suspend_account",
      taxonomy: "harassment",
      rationale: "",
    }));
  });

  test("builds immutable audit evidence without mutable secrets", () => {
    const record = buildModerationAuditRecord({
      operatorUid: "operator-a",
      operatorRole: "moderator",
      decision: {
        actionId: "action-a",
        reportId: "report-a",
        action: "remove_content",
        taxonomy: "harassment",
        rationale: "Evidence reviewed.",
      },
      report: {
        reporterUid: "reporter-a",
        targetType: "message",
        targetId: "message-a",
        groupId: "group-a",
        evidence: { excerpt: "bounded evidence" },
      },
      now: { seconds: 1 },
    });
    assert.equal(record.schemaVersion, 1);
    assert.equal(record.operatorUid, "operator-a");
    assert.equal(record.reportSnapshot.targetId, "message-a");
    assert.equal(record.createdAt.seconds, 1);
  });
});
