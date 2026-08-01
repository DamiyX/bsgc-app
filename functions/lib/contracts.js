const crypto = require("node:crypto");

const GROUP_CAPACITY = 12;
const INVITE_TOKEN_BYTES = 32;
const MAX_INVITE_LIFETIME_HOURS = 24 * 30;
const MAX_MESSAGE_PREVIEW_LENGTH = 80;

function requireString(value, field, maxLength, { minLength = 1 } = {}) {
  if (typeof value !== "string") {
    throw new TypeError(`${field} must be a string`);
  }

  const normalized = value.trim();
  if (normalized.length < minLength || normalized.length > maxLength) {
    throw new RangeError(
      `${field} must contain ${minLength}-${maxLength} characters`,
    );
  }
  return normalized;
}

function optionalString(value, field, maxLength) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  return requireString(value, field, maxLength);
}

function requireInteger(
  value,
  field,
  { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER } = {},
) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`${field} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function createInviteToken() {
  return crypto.randomBytes(INVITE_TOKEN_BYTES).toString("base64url");
}

function hashInviteToken(token) {
  const normalized = requireString(token, "token", 512, { minLength: 32 });
  return crypto.createHash("sha256").update(normalized).digest("hex");
}

function connectionDocument(uid, otherUid, acceptedAt, sourceInviteId) {
  return {
    schemaVersion: 2,
    otherUid,
    status: "accepted",
    acceptedAt,
    source: "group_invite",
    sourceInviteId,
  };
}

function messagePreview(parts) {
  if (!Array.isArray(parts) || parts.length === 0) {
    return "Sent a message";
  }

  const firstPart = parts[0];
  if (!firstPart || typeof firstPart !== "object") {
    return "Sent a message";
  }

  if (firstPart.type === "voice") return "Voice note";
  if (firstPart.type === "image") return "Image";

  if (firstPart.type !== "text" || typeof firstPart.content !== "string") {
    return "Sent a message";
  }

  const singleLine = firstPart.content.replace(/\s+/g, " ").trim();
  if (!singleLine) return "Sent a message";
  if (singleLine.length <= MAX_MESSAGE_PREVIEW_LENGTH) return singleLine;
  return `${singleLine.slice(0, MAX_MESSAGE_PREVIEW_LENGTH - 1)}…`;
}

function messageNotificationData({ groupId, messageId, space }) {
  const normalizedGroupId = requireString(groupId, "groupId", 160);
  const normalizedMessageId = requireString(messageId, "messageId", 160);
  if (!["reflection", "discussion", "prayer"].includes(space)) {
    throw new RangeError("space is not supported");
  }
  return {
    version: "1",
    type: "group_message",
    groupId: normalizedGroupId,
    messageId: normalizedMessageId,
    space,
  };
}

function isInvalidMessagingTokenError(errorCode) {
  return [
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
  ].includes(errorCode);
}

function parseMessageAssetPath(objectName) {
  if (typeof objectName !== "string") return null;
  const match = objectName.match(
    /^groups\/([A-Za-z0-9_-]{1,160})\/messages\/([A-Za-z0-9_-]{1,160})\/([A-Za-z0-9_.-]{1,160})$/,
  );
  if (!match) return null;
  return {
    groupId: match[1],
    messageId: match[2],
    assetId: match[3],
  };
}

function normalizeInsightInput(data) {
  const title = requireString(data?.title, "title", 160);
  const body = requireString(data?.body, "body", 12000);
  const themeId = optionalString(data?.themeId, "themeId", 64) ?? "theme_0";
  if (!/^theme_[0-5]$/.test(themeId)) {
    throw new RangeError("themeId is not supported");
  }
  return { title, body, themeId };
}

function normalizeReportInput(data) {
  const targetType = requireString(data?.targetType, "targetType", 20);
  if (!["user", "group", "message", "insight", "comment"].includes(
    targetType,
  )) {
    throw new RangeError("targetType is not supported");
  }
  const targetId = requireString(data?.targetId, "targetId", 256);
  const groupId = optionalString(data?.groupId, "groupId", 160);
  const insightId = optionalString(data?.insightId, "insightId", 160);
  if (targetType === "comment" && !insightId) {
    throw new RangeError("insightId is required for comment reports");
  }
  if (targetType !== "comment" && insightId) {
    throw new RangeError("insightId is only supported for comment reports");
  }
  const reason = requireString(data?.reason, "reason", 40);
  if (![
    "spam",
    "harassment",
    "hate",
    "sexual_content",
    "violence",
    "self_harm",
    "misinformation",
    "other",
  ].includes(reason)) {
    throw new RangeError("reason is not supported");
  }
  const details = optionalString(data?.details, "details", 2000);
  return { targetType, targetId, groupId, insightId, reason, details };
}

module.exports = {
  GROUP_CAPACITY,
  MAX_INVITE_LIFETIME_HOURS,
  connectionDocument,
  createInviteToken,
  hashInviteToken,
  isInvalidMessagingTokenError,
  messageNotificationData,
  messagePreview,
  normalizeInsightInput,
  normalizeReportInput,
  optionalString,
  parseMessageAssetPath,
  requireInteger,
  requireString,
};
