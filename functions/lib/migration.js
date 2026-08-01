"use strict";

const crypto = require("node:crypto");

const DAY_MILLIS = 24 * 60 * 60 * 1000;
const GROUP_CAPACITY = 12;
const INVITE_COLLECTION = "invites";

function cleanString(value, maxLength, { fallback = null } = {}) {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim();
  if (!trimmed) return fallback;
  return [...trimmed].slice(0, maxLength).join("");
}

function boundedString(value, maxLength, fallback = "") {
  if (typeof value !== "string") return fallback;
  return [...value].slice(0, maxLength).join("");
}

function uniqueStrings(values, maxItems, maxLength) {
  if (!Array.isArray(values)) return [];
  return [
    ...new Set(
      values
        .map((value) => cleanString(value, maxLength))
        .filter(Boolean),
    ),
  ].slice(0, maxItems);
}

function isTimestamp(value) {
  return Boolean(value && typeof value.toMillis === "function"
    && Number.isFinite(value.toMillis()));
}

function timestampOr(value, fallback) {
  return isTimestamp(value) ? value : fallback;
}

function integerInRange(value, fallback, min, max) {
  const parsed = Number.isInteger(value)
    ? value
    : (typeof value === "string" && /^-?\d+$/.test(value)
      ? Number(value)
      : fallback);
  return Math.min(Math.max(parsed, min), max);
}

function timestampAfter(base, millis, fromMillis) {
  const target = base.toMillis() + millis;
  if (typeof fromMillis === "function") return fromMillis(target);
  if (base.constructor && typeof base.constructor.fromMillis === "function") {
    return base.constructor.fromMillis(target);
  }
  return { toMillis: () => target };
}

function deriveUserDocuments(uid, legacy, timestamp) {
  const displayName = cleanString(legacy.displayName, 80, {
    fallback: "Believer",
  });
  const photoUrl = cleanString(
    legacy.photoUrl ?? legacy.photoURL,
    2048,
  );
  const bio = cleanString(legacy.bio, 300);
  const email = cleanString(legacy.email, 320);
  const phoneNumbers = uniqueStrings(
    legacy.phoneNumbers ?? (legacy.phone ? [legacy.phone] : []),
    5,
    32,
  );
  const referredBy = cleanString(legacy.referredBy, 128);
  const createdAt = timestampOr(legacy.createdAt, timestamp);

  return {
    public: {
      schemaVersion: 2,
      uid,
      displayName,
      ...(photoUrl ? { photoUrl } : {}),
      ...(bio ? { bio } : {}),
      createdAt,
      updatedAt: timestamp,
    },
    private: {
      schemaVersion: 2,
      uid,
      ...(email ? { email } : {}),
      ...(phoneNumbers.length ? { phoneNumbers } : {}),
      phoneVerified: legacy.phoneVerified === true,
      contactDiscoveryConsent: legacy.contactDiscoveryConsent === true,
      connectionCount: integerInRange(
        legacy.connectionCount,
        0,
        0,
        500,
      ),
      ...(referredBy ? { referredBy } : {}),
      onboardingComplete: legacy.onboardingComplete === true,
      deletionState: cleanString(legacy.deletionState, 32, {
        fallback: "active",
      }),
      ...(legacy.notificationPreferences
        && typeof legacy.notificationPreferences === "object"
        && !Array.isArray(legacy.notificationPreferences)
        ? { notificationPreferences: legacy.notificationPreferences }
        : {}),
      ...(legacy.storagePreferences
        && typeof legacy.storagePreferences === "object"
        && !Array.isArray(legacy.storagePreferences)
        ? { storagePreferences: legacy.storagePreferences }
        : {}),
      createdAt,
      updatedAt: timestamp,
    },
    legacyFcmToken: cleanString(legacy.fcmToken, 4096),
  };
}

function deriveLifecycle(group, nowMillis) {
  if (["draft", "scheduled", "active", "completed", "archived"].includes(
    group.lifecycle,
  )) {
    return group.lifecycle;
  }
  const startMillis = group.startDate?.toMillis?.() ?? null;
  const endMillis = group.endDate?.toMillis?.() ?? null;
  if (endMillis !== null && endMillis <= nowMillis) return "completed";
  if (startMillis !== null && startMillis > nowMillis) return "scheduled";
  return "active";
}

function memberNumberMap(raw, members, normalizer, defaultValue) {
  const source = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw
    : {};
  return Object.fromEntries(
    members.map((uid) => [uid, normalizer(source[uid], defaultValue)]),
  );
}

function normalizeProgress(value) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(Math.max(value, 0), 1)
    : 0;
}

function normalizeUnread(value) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(Math.max(Math.trunc(value), 0), Number.MAX_SAFE_INTEGER)
    : 0;
}

function normalizeChapters(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter(
    (chapter) => Number.isInteger(chapter) && chapter >= 1,
  ))].sort((left, right) => left - right);
}

function deriveGroupMigration(groupId, group, timestamp) {
  const members = uniqueStrings(group.members, GROUP_CAPACITY, 128);
  if (members.length === 0) {
    return {
      issue: {
        document: `groups/${groupId}`,
        code: "missing-members",
        message: "Cannot infer a safe owner for a group without members.",
      },
    };
  }

  const ownerId = cleanString(group.ownerId, 128) ?? members[0];
  if (!members.includes(ownerId)) {
    return {
      issue: {
        document: `groups/${groupId}`,
        code: "owner-not-member",
        message: "Existing ownerId is not present in the member summary.",
      },
    };
  }

  const groupType = group.groupType === "Topic"
    || group.groupType === "Devotional"
    || cleanString(group.topic, 200)
    ? "Topic"
    : "Bible";
  const name = cleanString(group.name, 80, { fallback: "Study group" });
  const description = boundedString(group.description, 1000);
  const photoUrl = cleanString(group.photoUrl ?? group.groupPhotoUrl, 2048);
  const pinnedScripture = boundedString(group.pinnedScripture, 200);
  const topic = cleanString(group.topic, 200);
  const studyBook = cleanString(group.studyBook ?? group.book, 80);
  const createdAt = timestampOr(group.createdAt, timestamp);

  const canonical = {
    schemaVersion: 2,
    ownerId,
    name,
    members,
    readingProgress: memberNumberMap(
      group.readingProgress,
      members,
      normalizeProgress,
      0,
    ),
    userCompletedChapters: memberNumberMap(
      group.userCompletedChapters,
      members,
      normalizeChapters,
      [],
    ),
    unreadCounts: memberNumberMap(
      group.unreadCounts,
      members,
      normalizeUnread,
      0,
    ),
    pinnedScripture,
    description,
    ...(photoUrl ? { photoUrl } : {}),
    createdAt,
    groupType,
    ...(topic ? { topic } : {}),
    ...(studyBook ? { studyBook } : {}),
    ...(Number.isInteger(group.totalChapters)
      ? { totalChapters: Math.max(group.totalChapters, 0) }
      : {}),
    ...(isTimestamp(group.startDate) ? { startDate: group.startDate } : {}),
    ...(isTimestamp(group.endDate) ? { endDate: group.endDate } : {}),
    lifecycle: deriveLifecycle(group, timestamp.toMillis()),
    extensionCount: integerInRange(group.extensionCount, 0, 0, 3),
  };
  for (const [field, maxLength] of [
    ["lastMessageText", 8000],
    ["lastMessageSenderName", 80],
    ["lastMessageSenderId", 128],
  ]) {
    const value = cleanString(group[field], maxLength);
    if (value) canonical[field] = value;
  }
  if (isTimestamp(group.lastMessageTime)) {
    canonical.lastMessageTime = group.lastMessageTime;
  }

  const issues = validateCanonicalDocument("group", canonical);
  if (issues.length) return canonicalizationIssue(`groups/${groupId}`, issues);
  return {
    group: canonical,
    members: members.map((uid) => ({
      uid,
      schemaVersion: 2,
      role: uid === ownerId ? "owner" : "member",
      status: "active",
      joinedAt: timestampOr(group.createdAt, timestamp),
      invitedBy: ownerId,
    })),
  };
}

function deriveInsightMigration(insight, timestamp, options = {}) {
  const authorUid = cleanString(
    insight.authorUid ?? insight.userId ?? insight.authorId,
    128,
  );
  const body = boundedString(insight.body ?? insight.content, 12000);
  if (!authorUid || !body) {
    return canonicalizationIssue("insights", [
      !authorUid ? "authorUid" : "body",
    ], "invalid-insight");
  }
  const createdAt = timestampOr(insight.createdAt, timestamp);
  const canonical = {
    schemaVersion: 2,
    authorUid,
    authorName: cleanString(
      insight.authorName ?? insight.userName,
      80,
      { fallback: "Believer" },
    ),
    ...(cleanString(
      insight.authorPhotoUrl ?? insight.userPhotoUrl ?? insight.userPhotoURL,
      2048,
    ) ? {
        authorPhotoUrl: cleanString(
          insight.authorPhotoUrl
            ?? insight.userPhotoUrl
            ?? insight.userPhotoURL,
          2048,
        ),
      } : {}),
    title: boundedString(insight.title, 160),
    body,
    themeId: cleanString(
      insight.themeId ?? insight.themeColor,
      64,
      { fallback: "theme_0" },
    ),
    audience: "contacts",
    status: insight.status === "deleted" ? "deleted" : "active",
    createdAt,
    updatedAt: timestampOr(insight.updatedAt, createdAt),
    expiresAt: isTimestamp(insight.expiresAt)
      ? insight.expiresAt
      : timestampAfter(createdAt, 3 * DAY_MILLIS, options.fromMillis),
    ...(Array.isArray(insight.seenBy)
      ? { seenBy: uniqueStrings(insight.seenBy, 10000, 128) }
      : {}),
    ...(Array.isArray(insight.likedBy)
      ? { likedBy: uniqueStrings(insight.likedBy, 10000, 128) }
      : {}),
  };
  const issues = validateCanonicalDocument("insight", canonical);
  return issues.length
    ? canonicalizationIssue("insights", issues, "invalid-insight")
    : { insight: canonical };
}

function deriveNoteMigration(uid, note, timestamp) {
  const body = typeof note.body === "string" ? note.body : "";
  if (body.length === 0) {
    return canonicalizationIssue("notes", ["body"], "empty-note-body");
  }
  if (body.length > 50000) {
    return canonicalizationIssue(
      "notes",
      ["body"],
      "note-body-limit-exceeded",
    );
  }
  const createdAt = timestampOr(note.createdAt, timestamp);
  const canonical = {
    schemaVersion: 2,
    authorUid: uid,
    title: cleanString(note.title, 160, { fallback: "" }),
    body,
    themeId: cleanString(note.themeId ?? note.themeColor, 64, {
      fallback: "theme_0",
    }),
    createdAt,
    updatedAt: timestampOr(note.updatedAt, createdAt),
  };
  const issues = validateCanonicalDocument("note", canonical);
  return issues.length ? canonicalizationIssue("notes", issues) : canonical;
}

function deriveSavedInsightMigration(insightId, saved, timestamp) {
  return {
    insightId,
    savedAt: timestampOr(saved.savedAt ?? saved.createdAt, timestamp),
  };
}

function normalizeMessageParts(messageId, groupId, message) {
  let parts = Array.isArray(message.parts) ? message.parts : null;
  if (!parts) {
    parts = [{
      type: ["text", "voice", "image"].includes(message.type)
        ? message.type
        : "text",
      content: typeof message.content === "string" ? message.content : "",
      ...(Number.isInteger(message.durationSeconds)
        ? { durationSeconds: message.durationSeconds }
        : {}),
      ...(cleanString(message.assetId, 768)
        ? { assetId: cleanString(message.assetId, 768) }
        : {}),
    }];
  }
  return parts.slice(0, 4).map((part) => {
    const type = ["text", "voice", "image"].includes(part?.type)
      ? part.type
      : "text";
    const normalized = {
      type,
      content: boundedString(part?.content, 8000),
    };
    for (const [field, maxLength] of [["assetId", 768], ["fileName", 180]]) {
      const value = cleanString(part?.[field], maxLength);
      if (value) normalized[field] = value;
    }
    if (type === "voice" && Number.isInteger(part?.durationSeconds)) {
      normalized.durationSeconds = integerInRange(
        part.durationSeconds,
        1,
        1,
        300,
      );
      const caption = cleanString(part?.caption, 1000);
      if (caption) normalized.caption = caption;
    }
    if (Number.isInteger(part?.sizeBytes)) {
      normalized.sizeBytes = integerInRange(
        part.sizeBytes,
        1,
        1,
        25 * 1024 * 1024,
      );
    }
    return normalized;
  }).filter((part) => part.content);
}

function deriveMessageMigration(messageId, message, timestamp, options = {}) {
  const senderId = cleanString(
    message.senderId ?? message.authorUid ?? message.userId,
    128,
  );
  if (!senderId) {
    return canonicalizationIssue(
      "messages",
      ["senderId"],
      "missing-message-sender",
    );
  }
  const isDeleted = message.isDeleted === true;
  const parts = isDeleted
    ? []
    : normalizeMessageParts(messageId, options.groupId, message);
  if (!isDeleted && parts.length === 0) {
    return canonicalizationIssue("messages", ["parts"], "empty-message");
  }
  const unsafeMedia = parts.find((part) => {
    if (!["voice", "image"].includes(part.type)) return false;
    const expectedPrefix = options.groupId
      ? `groups/${options.groupId}/messages/${messageId}/`
      : null;
    return !expectedPrefix
      || !part.content.startsWith(expectedPrefix)
      || !part.assetId;
  });
  if (unsafeMedia) {
    const code = /^https:\/\//i.test(unsafeMedia.content)
      ? "external-media-requires-storage-migration"
      : `inline-${unsafeMedia.type}-requires-storage-migration`;
    return canonicalizationIssue("messages", ["parts"], code);
  }
  const canonical = {
    schemaVersion: 2,
    clientMessageId: cleanString(message.clientMessageId, 128) ?? messageId,
    space: ["reflection", "discussion", "prayer"].includes(message.space)
      ? message.space
      : "discussion",
    senderId,
    senderName: cleanString(
      message.senderName ?? message.authorName ?? message.userName,
      80,
      { fallback: "Braid member" },
    ),
    ...(cleanString(
      message.senderPhotoUrl
        ?? message.senderPhotoURL
        ?? message.authorPhotoUrl,
      2048,
    ) ? {
        senderPhotoUrl: cleanString(
          message.senderPhotoUrl
            ?? message.senderPhotoURL
            ?? message.authorPhotoUrl,
          2048,
        ),
      } : {}),
    ...(cleanString(message.replyToMessageId, 128)
      ? { replyToMessageId: cleanString(message.replyToMessageId, 128) }
      : {}),
    parts,
    ...(isTimestamp(message.clientCreatedAt)
      ? { clientCreatedAt: message.clientCreatedAt }
      : {}),
    timestamp: timestampOr(message.timestamp ?? message.createdAt, timestamp),
    isEdited: message.isEdited === true,
    isDeleted,
  };
  const issues = validateCanonicalDocument("message", canonical);
  return issues.length
    ? canonicalizationIssue("messages", issues, "invalid-message")
    : { message: canonical };
}

function validateManagedMessageAsset(
  part,
  metadata,
  { groupId, messageId, senderId },
) {
  const issues = [];
  const add = (condition, field) => {
    if (!condition) issues.push(field);
  };
  add(metadata && typeof metadata === "object", "managedAsset");
  if (!metadata || typeof metadata !== "object") return issues;
  add(metadata.assetId === part.assetId, "assetId");
  add(metadata.storagePath === part.content, "storagePath");
  add(metadata.ownerUid === senderId, "ownerUid");
  add(metadata.entityType === "message", "entityType");
  add(metadata.entityId === messageId, "entityId");
  add(metadata.groupId === groupId, "groupId");
  add(["pending", "committed"].includes(metadata.status), "status");
  add(Number.isInteger(metadata.sizeBytes)
    && metadata.sizeBytes >= 1
    && (part.type === "image"
      ? metadata.sizeBytes <= 10 * 1024 * 1024
      : metadata.sizeBytes <= 25 * 1024 * 1024), "sizeBytes");
  add(typeof metadata.mimeType === "string"
    && (part.type === "image"
      ? /^image\/(jpeg|png|webp)$/.test(metadata.mimeType)
      : /^audio\/(aac|m4a|mp4|mpeg|ogg|wav|webm)$/.test(metadata.mimeType)),
  "mimeType");
  return [...new Set(issues)];
}

function canonicalInvitePath(inviteId) {
  return `${INVITE_COLLECTION}/${inviteId}`;
}

function deriveInviteMigration(inviteId, invite, timestamp) {
  const groupId = cleanString(invite.groupId ?? invite.group, 128);
  const createdBy = cleanString(
    invite.createdBy ?? invite.inviterId ?? invite.ownerId,
    128,
  );
  if (!groupId || !createdBy) {
    return canonicalizationIssue(
      "invites",
      [!groupId ? "groupId" : "createdBy"],
      "invalid-invite",
    );
  }
  const canonicalId = /^[a-f0-9]{64}$/i.test(inviteId)
    ? inviteId.toLowerCase()
    : crypto.createHash("sha256").update(inviteId).digest("hex");
  const maxUses = integerInRange(invite.maxUses, 1, 1, GROUP_CAPACITY - 1);
  const useCount = integerInRange(
    invite.useCount ?? invite.uses,
    0,
    0,
    maxUses,
  );
  const createdAt = timestampOr(invite.createdAt, timestamp);
  const canonical = {
    schemaVersion: 2,
    groupId,
    createdBy,
    createdAt,
    expiresAt: timestampOr(
      invite.expiresAt,
      timestampAfter(createdAt, 72 * 60 * 60 * 1000),
    ),
    maxUses,
    useCount,
    revokedAt: isTimestamp(invite.revokedAt) ? invite.revokedAt : null,
  };
  const issues = validateCanonicalDocument("invite", canonical);
  return issues.length
    ? canonicalizationIssue(canonicalInvitePath(canonicalId), issues)
    : { inviteId: canonicalId, invite: canonical };
}

function canonicalizationIssue(document, fields, code = "invalid-canonical") {
  return {
    issue: {
      document,
      code,
      fields,
      message: `Canonical validation failed for: ${fields.join(", ")}.`,
    },
  };
}

function validString(value, min, max) {
  return typeof value === "string"
    && value.length >= min
    && value.length <= max;
}

function exactKeys(data, required, allowed) {
  const keys = Object.keys(data);
  return required.filter((key) => !keys.includes(key))
    .concat(keys.filter((key) => !allowed.includes(key)));
}

function validateCanonicalDocument(kind, data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return ["data"];
  const issues = [];
  const add = (condition, field) => {
    if (!condition && !issues.includes(field)) issues.push(field);
  };
  if (kind === "publicUser") {
    issues.push(...exactKeys(
      data,
      ["schemaVersion", "uid", "displayName", "updatedAt"],
      ["schemaVersion", "uid", "displayName", "photoUrl", "bio", "createdAt",
        "updatedAt"],
    ));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.uid, 1, 128), "uid");
    add(validString(data.displayName, 1, 80), "displayName");
    add(isTimestamp(data.updatedAt), "updatedAt");
    add(!("photoUrl" in data) || validString(data.photoUrl, 1, 2048),
      "photoUrl");
    add(!("bio" in data) || validString(data.bio, 1, 300), "bio");
  } else if (kind === "privateUser") {
    issues.push(...exactKeys(
      data,
      ["schemaVersion", "uid", "updatedAt"],
      ["schemaVersion", "uid", "email", "phoneNumbers", "phoneVerified",
        "contactDiscoveryConsent", "connectionCount", "referredBy",
        "onboardingComplete", "deletionState", "notificationPreferences",
        "storagePreferences", "createdAt", "updatedAt"],
    ));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.uid, 1, 128), "uid");
    add(isTimestamp(data.updatedAt), "updatedAt");
    add(!("email" in data) || validString(data.email, 1, 320), "email");
    add(!("phoneNumbers" in data)
      || Array.isArray(data.phoneNumbers)
      && data.phoneNumbers.length <= 5
      && data.phoneNumbers.every((phone) => validString(phone, 1, 32)),
    "phoneNumbers");
    for (const field of [
      "phoneVerified",
      "contactDiscoveryConsent",
      "onboardingComplete",
    ]) {
      add(!(field in data) || typeof data[field] === "boolean", field);
    }
    add(!("deletionState" in data)
      || validString(data.deletionState, 1, 32), "deletionState");
    add(!("connectionCount" in data)
      || Number.isInteger(data.connectionCount)
      && data.connectionCount >= 0
      && data.connectionCount <= 500, "connectionCount");
  } else if (kind === "group") {
    const required = ["schemaVersion", "ownerId", "name", "members",
      "readingProgress", "userCompletedChapters", "unreadCounts",
      "pinnedScripture", "description", "createdAt", "groupType", "lifecycle",
      "extensionCount"];
    const allowed = required.concat(["photoUrl", "topic", "studyBook",
      "totalChapters", "startDate", "endDate", "lastMessageTime",
      "lastMessageText", "lastMessageSenderName", "lastMessageSenderId"]);
    issues.push(...exactKeys(data, required, allowed));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.ownerId, 1, 128), "ownerId");
    add(validString(data.name, 1, 80), "name");
    add(Array.isArray(data.members) && data.members.length >= 1
      && data.members.length <= GROUP_CAPACITY
      && data.members.includes(data.ownerId), "members");
    add(validString(data.description, 0, 1000), "description");
    add(["Bible", "Topic"].includes(data.groupType), "groupType");
    add(["draft", "scheduled", "active", "completed", "archived"].includes(
      data.lifecycle,
    ), "lifecycle");
    add(Number.isInteger(data.extensionCount)
      && data.extensionCount >= 0 && data.extensionCount <= 3, "extensionCount");
    for (const field of [
      "readingProgress",
      "userCompletedChapters",
      "unreadCounts",
    ]) {
      add(data[field] && typeof data[field] === "object"
        && !Array.isArray(data[field])
        && data.members.every((uid) => Object.hasOwn(data[field], uid))
        && Object.keys(data[field]).every((uid) => data.members.includes(uid)),
      field);
    }
    add(Object.values(data.readingProgress ?? {}).every(
      (value) => typeof value === "number" && value >= 0 && value <= 1,
    ), "readingProgress");
    add(Object.values(data.userCompletedChapters ?? {}).every(
      (value) => Array.isArray(value)
        && value.every((chapter) => Number.isInteger(chapter) && chapter >= 1),
    ), "userCompletedChapters");
    add(Object.values(data.unreadCounts ?? {}).every(
      (value) => Number.isInteger(value) && value >= 0,
    ), "unreadCounts");
  } else if (kind === "note") {
    const keys = ["schemaVersion", "authorUid", "title", "body", "themeId",
      "createdAt", "updatedAt"];
    issues.push(...exactKeys(data, keys, keys));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.authorUid, 1, 128), "authorUid");
    add(validString(data.title, 0, 160), "title");
    add(validString(data.body, 1, 50000), "body");
    add(validString(data.themeId, 0, 64), "themeId");
    add(isTimestamp(data.createdAt), "createdAt");
    add(isTimestamp(data.updatedAt), "updatedAt");
  } else if (kind === "message") {
    const required = ["schemaVersion", "senderId", "senderName", "parts",
      "timestamp"];
    const allowed = required.concat(["clientMessageId", "space",
      "senderPhotoUrl", "replyToMessageId", "clientCreatedAt", "isEdited",
      "isDeleted"]);
    issues.push(...exactKeys(data, required, allowed));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.senderId, 1, 128), "senderId");
    add(validString(data.senderName, 1, 80), "senderName");
    add(isTimestamp(data.timestamp), "timestamp");
    add(Array.isArray(data.parts) && data.parts.length <= 4
      && (data.isDeleted === true || data.parts.length >= 1), "parts");
    if (Array.isArray(data.parts)) {
      for (const part of data.parts) {
        const partKeys = part && typeof part === "object"
          ? Object.keys(part)
          : [];
        add(part && typeof part === "object"
          && ["text", "voice", "image"].includes(part.type)
          && validString(part.content, 1, 8000)
          && partKeys.every((key) => [
            "type",
            "content",
            "assetId",
            "durationSeconds",
            "caption",
            "fileName",
            "sizeBytes",
          ].includes(key))
          && (part.type === "voice"
            ? Number.isInteger(part.durationSeconds)
              && part.durationSeconds >= 1
              && part.durationSeconds <= 300
              && (!('caption' in part)
                || validString(part.caption, 1, 1000))
            : !("durationSeconds" in part))
          && (part.type === "text"
            ? !("assetId" in part)
            : validString(part.assetId, 1, 768)), "parts");
      }
    }
  } else if (kind === "insight") {
    const required = ["schemaVersion", "authorUid", "authorName", "title",
      "body", "themeId", "audience", "status", "createdAt", "updatedAt",
      "expiresAt"];
    const allowed = required.concat(["authorPhotoUrl", "seenBy", "likedBy"]);
    issues.push(...exactKeys(data, required, allowed));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.authorUid, 1, 128), "authorUid");
    add(validString(data.authorName, 1, 80), "authorName");
    add(validString(data.title, 0, 160), "title");
    add(validString(data.body, 1, 12000), "body");
    add(validString(data.themeId, 0, 64), "themeId");
    add(data.audience === "contacts", "audience");
    add(["active", "deleted"].includes(data.status), "status");
    for (const field of ["createdAt", "updatedAt", "expiresAt"]) {
      add(isTimestamp(data[field]), field);
    }
    add(!("seenBy" in data) || Array.isArray(data.seenBy), "seenBy");
    add(!("likedBy" in data) || Array.isArray(data.likedBy), "likedBy");
  } else if (kind === "invite") {
    const keys = ["schemaVersion", "groupId", "createdBy", "createdAt",
      "expiresAt", "maxUses", "useCount", "revokedAt"];
    issues.push(...exactKeys(data, keys, keys));
    add(data.schemaVersion === 2, "schemaVersion");
    add(validString(data.groupId, 1, 128), "groupId");
    add(validString(data.createdBy, 1, 128), "createdBy");
    add(isTimestamp(data.createdAt), "createdAt");
    add(isTimestamp(data.expiresAt), "expiresAt");
    add(Number.isInteger(data.maxUses) && data.maxUses >= 1
      && data.maxUses < GROUP_CAPACITY, "maxUses");
    add(Number.isInteger(data.useCount) && data.useCount >= 0
      && data.useCount <= data.maxUses, "useCount");
    add(data.revokedAt === null || isTimestamp(data.revokedAt), "revokedAt");
  } else {
    issues.push("kind");
  }
  return [...new Set(issues)];
}

module.exports = {
  GROUP_CAPACITY,
  INVITE_COLLECTION,
  canonicalInvitePath,
  deriveGroupMigration,
  deriveInsightMigration,
  deriveInviteMigration,
  deriveLifecycle,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
  validateManagedMessageAsset,
  validateCanonicalDocument,
};
