function cleanString(value, maxLength) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, maxLength);
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

function deriveUserDocuments(uid, legacy, timestamp) {
  const displayName = cleanString(legacy.displayName, 80) ?? "Believer";
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

  return {
    public: {
      schemaVersion: 2,
      uid,
      displayName,
      ...(photoUrl ? { photoUrl } : {}),
      ...(bio ? { bio } : {}),
      createdAt: legacy.createdAt ?? timestamp,
      updatedAt: timestamp,
    },
    private: {
      schemaVersion: 2,
      uid,
      ...(email ? { email } : {}),
      ...(phoneNumbers.length ? { phoneNumbers } : {}),
      phoneVerified: false,
      contactDiscoveryConsent: false,
      connectionCount: 0,
      ...(referredBy ? { referredBy } : {}),
      onboardingComplete: legacy.onboardingComplete === true,
      deletionState: "active",
      createdAt: legacy.createdAt ?? timestamp,
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
  if (endMillis && endMillis <= nowMillis) return "completed";
  if (startMillis && startMillis > nowMillis) return "scheduled";
  return "active";
}

function deriveGroupMigration(groupId, group, timestamp) {
  const members = uniqueStrings(group.members, 12, 128);
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

  return {
    group: {
      schemaVersion: 2,
      ownerId,
      members,
      lifecycle: deriveLifecycle(group, timestamp.toMillis()),
      extensionCount: Number.isInteger(group.extensionCount)
        ? Math.min(Math.max(group.extensionCount, 0), 3)
        : 0,
    },
    members: members.map((uid) => ({
      uid,
      schemaVersion: 2,
      role: uid === ownerId ? "owner" : "member",
      status: "active",
      joinedAt: group.createdAt ?? timestamp,
      invitedBy: ownerId,
    })),
  };
}

function deriveInsightMigration(insight, timestamp) {
  return {
    schemaVersion: 2,
    audience: "contacts",
    status: insight.status === "deleted" ? "deleted" : "active",
    updatedAt: insight.updatedAt ?? insight.createdAt ?? timestamp,
  };
}

function deriveNoteMigration(uid, note, timestamp) {
  const body = typeof note.body === "string" ? note.body.trim() : "";
  if (body.length > 50000) {
    return {
      issue: {
        code: "note-body-limit-exceeded",
        message:
          "Legacy note body exceeds 50,000 characters and requires manual review.",
      },
    };
  }

  return {
    schemaVersion: 2,
    authorUid: uid,
    title: cleanString(note.title, 160) ?? "",
    body,
    themeId: cleanString(note.themeId ?? note.themeColor, 64) ?? "theme_0",
    createdAt: note.createdAt ?? timestamp,
    updatedAt: note.updatedAt ?? note.createdAt ?? timestamp,
  };
}

function deriveSavedInsightMigration(insightId, saved, timestamp) {
  return {
    insightId,
    savedAt: saved.savedAt ?? saved.createdAt ?? timestamp,
  };
}

function deriveMessageMigration(messageId, message, timestamp) {
  const senderId = cleanString(
    message.senderId ?? message.authorUid ?? message.userId,
    128,
  );
  if (!senderId) {
    return {
      issue: {
        code: "missing-message-sender",
        message: "Message has no safely identifiable sender.",
      },
    };
  }

  const senderName = cleanString(
    message.senderName ?? message.authorName,
    80,
  ) ?? "Braid member";
  const senderPhotoUrl = cleanString(
    message.senderPhotoUrl ?? message.senderPhotoURL,
    2048,
  );
  const replyToMessageId = cleanString(message.replyToMessageId, 128);
  let parts = Array.isArray(message.parts) ? message.parts : null;
  if (!parts) {
    const type = ["text", "voice", "image"].includes(message.type)
      ? message.type
      : "text";
    parts = [{
      type,
      content: typeof message.content === "string" ? message.content : "",
      ...(Number.isInteger(message.durationSeconds)
        ? { durationSeconds: message.durationSeconds }
        : {}),
    }];
  }
  const boundedParts = parts.slice(0, 4).map((part) => ({
    type: ["text", "voice", "image"].includes(part?.type)
      ? part.type
      : "text",
    content: typeof part?.content === "string"
      ? part.content.slice(0, 8000)
      : "",
    ...(Number.isInteger(part?.durationSeconds)
      ? { durationSeconds: Math.min(Math.max(part.durationSeconds, 1), 300) }
      : {}),
  })).filter((part) => part.content);
  const hasInlineVoice = boundedParts.some(
    (part) => part.type === "voice"
      && !/^https:\/\//.test(part.content),
  );
  if (hasInlineVoice) {
    return {
      issue: {
        code: "inline-voice-requires-storage-migration",
        message:
          "Legacy inline voice data must be uploaded to Storage before v2 enforcement.",
      },
    };
  }
  const hasInlineImage = boundedParts.some(
    (part) => part.type === "image"
      && !/^https:\/\//.test(part.content),
  );
  if (hasInlineImage) {
    return {
      issue: {
        code: "inline-image-requires-storage-migration",
        message:
          "Legacy inline image data must be uploaded to Storage before v2 enforcement.",
      },
    };
  }
  const isDeleted = message.isDeleted === true;
  if (boundedParts.length === 0 && !isDeleted) {
    return {
      issue: {
        code: "empty-message",
        message: "Message has no safely migratable content.",
      },
    };
  }
  return {
    message: {
      schemaVersion: 2,
      clientMessageId: cleanString(message.clientMessageId, 128) ?? messageId,
      space: ["reflection", "discussion", "prayer"].includes(message.space)
        ? message.space
        : "discussion",
      senderId,
      senderName,
      ...(senderPhotoUrl ? { senderPhotoUrl } : {}),
      ...(replyToMessageId ? { replyToMessageId } : {}),
      parts: isDeleted ? [] : boundedParts,
      timestamp: message.timestamp ?? message.createdAt ?? timestamp,
      isEdited: message.isEdited === true,
      isDeleted,
    },
  };
}

module.exports = {
  deriveGroupMigration,
  deriveInsightMigration,
  deriveLifecycle,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
};
