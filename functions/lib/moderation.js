"use strict";

const ROLE_CAPABILITIES = Object.freeze({
  support: ["read_queue"],
  moderator: [
    "read_queue",
    "dismiss_report",
    "remove_content",
    "restrict_account",
  ],
  trust_safety_admin: [
    "read_queue",
    "dismiss_report",
    "remove_content",
    "restrict_account",
    "suspend_account",
    "restore_account",
  ],
});

const ACTIONS = new Set([
  "dismiss_report",
  "remove_content",
  "restrict_account",
  "suspend_account",
  "restore_account",
]);
const TAXONOMY = new Set([
  "spam",
  "harassment",
  "hate",
  "sexual_content",
  "violence",
  "self_harm",
  "misinformation",
  "privacy",
  "other",
]);

function moderationCapabilities(token) {
  const role = token?.moderationRole;
  return ROLE_CAPABILITIES[role] ? [...ROLE_CAPABILITIES[role]] : [];
}

function boundedString(value, field, maxLength, minLength = 1) {
  if (typeof value !== "string") throw new TypeError(`${field} is required.`);
  const normalized = value.trim();
  if (normalized.length < minLength || normalized.length > maxLength) {
    throw new RangeError(`${field} is invalid.`);
  }
  return normalized;
}

function normalizeModerationDecision(data) {
  const actionId = boundedString(data?.actionId, "actionId", 160);
  const reportId = boundedString(data?.reportId, "reportId", 160);
  const action = boundedString(data?.action, "action", 40);
  const taxonomy = boundedString(data?.taxonomy, "taxonomy", 40);
  const rationale = boundedString(data?.rationale, "rationale", 2_000, 10);
  if (!ACTIONS.has(action)) throw new RangeError("action is unsupported.");
  if (!TAXONOMY.has(taxonomy)) throw new RangeError("taxonomy is unsupported.");
  return { actionId, reportId, action, taxonomy, rationale };
}

function buildModerationAuditRecord({
  operatorUid,
  operatorRole,
  decision,
  report,
  now,
}) {
  return {
    schemaVersion: 1,
    operatorUid,
    operatorRole,
    action: decision.action,
    taxonomy: decision.taxonomy,
    rationale: decision.rationale,
    reportId: decision.reportId,
    actionId: decision.actionId,
    reportSnapshot: {
      reporterUid: report.reporterUid,
      targetType: report.targetType,
      targetId: report.targetId,
      ...(report.groupId ? { groupId: report.groupId } : {}),
      ...(report.insightId ? { insightId: report.insightId } : {}),
      ...(report.evidence?.ownerUid
        ? { ownerUid: report.evidence.ownerUid }
        : {}),
      ...(report.evidence ? { evidence: report.evidence } : {}),
      ...(report.accountStatusBefore
        ? { accountStatusBefore: report.accountStatusBefore }
        : {}),
    },
    createdAt: now,
  };
}

module.exports = {
  buildModerationAuditRecord,
  moderationCapabilities,
  normalizeModerationDecision,
};
