"use strict";

const { managedAssetIdForPath } = require("./managed_media");

const DAY_MS = 24 * 60 * 60 * 1000;
const ABUSE_POLICIES = Object.freeze({
  create_group: { windowMs: DAY_MS, limit: 5, minIntervalMs: 60_000 },
  create_group_invite: { windowMs: DAY_MS, limit: 30, minIntervalMs: 10_000 },
  redeem_group_invite: { windowMs: DAY_MS, limit: 40, minIntervalMs: 1_000 },
  send_group_message: { windowMs: DAY_MS, limit: 300, minIntervalMs: 750 },
  edit_group_message: { windowMs: DAY_MS, limit: 100, minIntervalMs: 2_000 },
  send_group_attachment: { windowMs: DAY_MS, limit: 50, minIntervalMs: 2_000 },
  create_insight_comment: { windowMs: DAY_MS, limit: 100, minIntervalMs: 2_000 },
  set_reaction: { windowMs: DAY_MS, limit: 500, minIntervalMs: 250 },
  submit_report: { windowMs: DAY_MS, limit: 20, minIntervalMs: 5_000 },
  publish_insight: { windowMs: DAY_MS, limit: 20, minIntervalMs: 30_000 },
  insight_fanout: { windowMs: DAY_MS, limit: 2_000, minIntervalMs: 0 },
});

function evaluateRateLimit(current, nowMillis, policy, cost = 1) {
  if (!Number.isFinite(nowMillis) || !policy) {
    throw new TypeError("A timestamp and rate policy are required.");
  }
  if (!Number.isInteger(cost) || cost < 1) {
    throw new RangeError("Rate-limit cost must be a positive integer.");
  }
  const hasWindowStart = Number.isFinite(current.windowStartedAtMillis);
  const windowStartedAtMillis = hasWindowStart
    ? current.windowStartedAtMillis
    : nowMillis;
  const withinWindow = hasWindowStart &&
    nowMillis - windowStartedAtMillis >= 0 &&
    nowMillis - windowStartedAtMillis < policy.windowMs;
  const count = withinWindow && Number.isInteger(current.count)
    ? current.count
    : 0;
  const lastActionAtMillis = Number.isFinite(current.lastActionAtMillis)
    ? current.lastActionAtMillis
    : 0;
  if (
    count > 0 &&
    policy.minIntervalMs > 0 &&
    nowMillis - lastActionAtMillis < policy.minIntervalMs
  ) {
    return {
      allowed: false,
      reason: "min_interval",
      retryAfterMillis: lastActionAtMillis + policy.minIntervalMs,
    };
  }
  if (count + cost > policy.limit) {
    return {
      allowed: false,
      reason: "window_limit",
      retryAfterMillis: windowStartedAtMillis + policy.windowMs,
    };
  }
  return {
    allowed: true,
    next: {
      windowStartedAtMillis: withinWindow ? windowStartedAtMillis : nowMillis,
      count: count + cost,
      lastActionAtMillis: nowMillis,
    },
  };
}

function requireId(value, field) {
  if (
    typeof value !== "string" ||
    !/^[A-Za-z0-9_-]{1,160}$/.test(value)
  ) {
    throw new RangeError(`${field} is invalid.`);
  }
  return value;
}

function normalizeGroupMessageInput(data) {
  const groupId = requireId(data?.groupId, "groupId");
  const messageId = requireId(data?.messageId, "messageId");
  const clientMessageId = data?.clientMessageId == null
    ? messageId
    : requireId(data.clientMessageId, "clientMessageId");
  const space = data?.space ?? "discussion";
  if (!["reflection", "discussion", "prayer"].includes(space)) {
    throw new RangeError("space is unsupported.");
  }
  if (!Array.isArray(data?.parts) || data.parts.length < 1 ||
      data.parts.length > 4) {
    throw new RangeError("parts must contain 1-4 items.");
  }
  let attachmentCount = 0;
  const parts = data.parts.map((part) => {
    if (!part || typeof part !== "object") {
      throw new TypeError("message part must be an object.");
    }
    if (part.type === "text") {
      if (
        typeof part.content !== "string" ||
        part.content.trim().length < 1 ||
        part.content.length > 8_000
      ) {
        throw new RangeError("text message content is invalid.");
      }
      return { type: "text", content: part.content };
    }
    if (!["image", "voice"].includes(part.type)) {
      throw new RangeError("message media type is unsupported.");
    }
    const expectedPrefix = `groups/${groupId}/messages/${messageId}/`;
    if (
      typeof part.content !== "string" ||
      !part.content.startsWith(expectedPrefix) ||
      !new RegExp(
        `^${expectedPrefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}` +
        "[A-Za-z0-9_.-]{1,160}$",
      ).test(part.content) ||
      part.assetId !== managedAssetIdForPath(part.content)
    ) {
      throw new RangeError("message media identity is invalid.");
    }
    const sizeLimit = part.type === "image"
      ? 10 * 1024 * 1024
      : 25 * 1024 * 1024;
    if (
      !Number.isInteger(part.sizeBytes) ||
      part.sizeBytes < 1 ||
      part.sizeBytes > sizeLimit
    ) {
      throw new RangeError("message media size is invalid.");
    }
    const normalized = {
      type: part.type,
      content: part.content,
      assetId: part.assetId,
      sizeBytes: part.sizeBytes,
    };
    if (part.type === "voice") {
      if (
        !Number.isInteger(part.durationSeconds) ||
        part.durationSeconds < 1 ||
        part.durationSeconds > 300
      ) {
        throw new RangeError("voice duration is invalid.");
      }
      normalized.durationSeconds = part.durationSeconds;
    }
    attachmentCount += 1;
    return normalized;
  });
  const replyToMessageId = data?.replyToMessageId == null
    ? null
    : requireId(data.replyToMessageId, "replyToMessageId");
  return {
    groupId,
    messageId,
    clientMessageId,
    space,
    parts,
    attachmentCount,
    ...(replyToMessageId ? { replyToMessageId } : {}),
  };
}

function reportTargetPath({ targetType, targetId, groupId, insightId }) {
  const id = requireId(targetId, "targetId");
  if (targetType === "user") return `users_public/${id}`;
  if (targetType === "group") return `groups/${id}`;
  if (targetType === "insight") return `insights/${id}`;
  if (targetType === "comment") {
    return `insights/${requireId(insightId, "insightId")}/comments/${id}`;
  }
  if (targetType === "message") {
    return `groups/${requireId(groupId, "groupId")}/messages/${id}`;
  }
  throw new RangeError("Report target type is unsupported.");
}

module.exports = {
  ABUSE_POLICIES,
  evaluateRateLimit,
  normalizeGroupMessageInput,
  reportTargetPath,
};
