const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { defineBoolean } = require("firebase-functions/params");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
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
  requireInteger,
  requireString,
} = require("./lib/contracts");
const {
  commitLifecycleUpdates,
} = require("./lib/lifecycle");
const {
  groupSummaryFromMessage,
  shouldReconcileGroupSummary,
} = require("./lib/group_summary");
const {
  buildGroupCoverAssetRecord,
  buildMessageAssetRecord,
  buildProfilePhotoAssetRecord,
  collectGroupCoverReference,
  collectMessageAssetReferences,
  collectProfilePhotoReference,
  reconcileExpiredManagedAsset,
  reconcileManagedReferences,
  registerManagedAsset,
} = require("./lib/managed_media");
const {
  createAccountDeletionHandlers,
  processDeletionStep,
} = require("./lib/account_deletion");
const {
  ABUSE_POLICIES,
  evaluateRateLimit,
  normalizeGroupMessageInput,
  reportTargetPath,
} = require("./lib/abuse_controls");
const {
  buildModerationAuditRecord,
  moderationCapabilities,
  normalizeModerationDecision,
} = require("./lib/moderation");
const {
  drainPagedJob,
} = require("./lib/scheduled_jobs");

admin.initializeApp();

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;
const enforceAppCheck = defineBoolean("ENFORCE_APP_CHECK", {
  default: false,
  description: "Reject callable requests without a valid App Check token.",
});
const enforceHighAbuseAppCheck = defineBoolean(
  "ENFORCE_HIGH_ABUSE_APP_CHECK",
  {
    default: false,
    description:
      "Staged App Check enforcement for abuse-prone callable functions.",
  },
);

const callableOptions = {
  region: "us-central1",
  enforceAppCheck,
};
const highAbuseCallableOptions = {
  region: "us-central1",
  enforceAppCheck: enforceHighAbuseAppCheck,
};

function authenticatedUid(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return uid;
}

function invalidArgument(error) {
  if (error instanceof TypeError || error instanceof RangeError) {
    return new HttpsError("invalid-argument", error.message);
  }
  return error;
}

function requireAccountPostingAccess(accountSnapshot) {
  if (!accountSnapshot?.exists) {
    throw new HttpsError(
      "failed-precondition",
      "Complete account setup before continuing.",
    );
  }
  const status = accountSnapshot.data().accountStatus ?? "active";
  if (status !== "active") {
    throw new HttpsError(
      "permission-denied",
      status === "suspended"
        ? "This account is suspended."
        : "This account is temporarily restricted from posting.",
      { accountStatus: status },
    );
  }
}

function boundedNotificationText(value, fallback) {
  if (typeof value !== "string") return fallback;
  const normalized = value.replace(/\s+/g, " ").trim();
  if (!normalized) return fallback;
  return normalized.length <= 80
    ? normalized
    : `${normalized.slice(0, 79)}…`;
}

async function mapInChunks(items, chunkSize, worker) {
  const results = [];
  for (let offset = 0; offset < items.length; offset += chunkSize) {
    const settled = await Promise.allSettled(
      items.slice(offset, offset + chunkSize).map(worker),
    );
    results.push(...settled);
  }
  return results;
}

async function sendAudienceNotification({
  recipientIds,
  type,
  title,
  fullBody,
  privateBody,
  data,
  preferenceField,
  channelId,
}) {
  if (recipientIds.length === 0) return;
  const queryResults = await mapInChunks(
    recipientIds,
    25,
    (uid) => db
      .collection(`users/${uid}/devices`)
      .where("notificationsEnabled", "==", true)
      .limit(10)
      .get(),
  );
  const snapshots = queryResults
    .filter((result) => result.status === "fulfilled")
    .map((result) => result.value);
  const devices = [];
  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) {
      const value = document.data();
      if (value[preferenceField] === false) continue;
      if (typeof value.token !== "string" || !value.token) continue;
      devices.push({
        token: value.token,
        reference: document.ref,
        previewContent: value.previewContent === true,
      });
    }
  }
  const uniqueDevices = [
    ...new Map(devices.map((device) => [device.token, device])).values(),
  ];
  const cleanup = [];
  let successCount = 0;
  let failureCount = 0;
  for (const previewContent of [true, false]) {
    const cohort = uniqueDevices.filter(
      (device) => device.previewContent === previewContent,
    );
    for (let offset = 0; offset < cohort.length; offset += 500) {
      const targetDevices = cohort.slice(offset, offset + 500);
      if (targetDevices.length === 0) continue;
      const response = await admin.messaging().sendEachForMulticast({
        notification: {
          title,
          body: previewContent ? fullBody : privateBody,
        },
        data: {
          type,
          ...data,
        },
        android: {
          notification: { channelId },
        },
        tokens: targetDevices.map((device) => device.token),
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
      response.responses.forEach((result, index) => {
        if (!result.success
          && isInvalidMessagingTokenError(result.error?.code)) {
          cleanup.push(targetDevices[index].reference.delete());
        }
      });
    }
  }
  await Promise.allSettled(cleanup);
  logger.info("Audience notification result", {
    type,
    recipientCount: recipientIds.length,
    deviceCount: uniqueDevices.length,
    successCount,
    failureCount,
    removedInvalidTokenCount: cleanup.length,
  });
}

async function requireGroupOwner(transaction, groupRef, uid) {
  const groupSnapshot = await transaction.get(groupRef);
  if (!groupSnapshot.exists) {
    throw new HttpsError("not-found", "Study group not found.");
  }

  const group = groupSnapshot.data();
  if (group.ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the study owner can perform this action.",
    );
  }
  return group;
}

async function enforceDailyRateLimit(
  transaction,
  uid,
  action,
  now,
  policy = ABUSE_POLICIES[action],
  cost = 1,
) {
  if (!policy) throw new Error(`Missing abuse policy for ${action}.`);
  const rateRef = db.doc(`rate_limits/${uid}/actions/${action}`);
  const rateSnapshot = await transaction.get(rateRef);
  const current = rateSnapshot.exists ? rateSnapshot.data() : {};
  const nowMillis = now.toMillis();
  const evaluation = evaluateRateLimit({
    windowStartedAtMillis: current.windowStartedAt?.toMillis?.(),
    lastActionAtMillis: current.lastActionAt?.toMillis?.()
      ?? current.lastCreatedAt?.toMillis?.(),
    count: current.count,
  }, nowMillis, policy, cost);
  if (!evaluation.allowed && evaluation.reason === "min_interval") {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait before trying that again.",
      {
        action,
        reason: evaluation.reason,
        retryAfterMillis: evaluation.retryAfterMillis,
      },
    );
  }
  if (!evaluation.allowed) {
    throw new HttpsError(
      "resource-exhausted",
      "Action limit reached. Please try again later.",
      {
        action,
        reason: evaluation.reason,
        retryAfterMillis: evaluation.retryAfterMillis,
      },
    );
  }
  transaction.set(
    rateRef,
    {
      windowStartedAt: Timestamp.fromMillis(
        evaluation.next.windowStartedAtMillis,
      ),
      count: evaluation.next.count,
      lastActionAt: now,
      action,
    },
    { merge: true },
  );
}

async function enforceInviteRateLimit(transaction, uid, now) {
  return enforceDailyRateLimit(
    transaction,
    uid,
    "create_group_invite",
    now,
  );
}

function validateManagedMessageAssets({ input, assets, uid }) {
  const parts = input.parts.filter((part) => part.assetId);
  for (let index = 0; index < assets.length; index += 1) {
    const asset = assets[index].exists ? assets[index].data() : null;
    const part = parts[index];
    if (
      !asset ||
      asset.assetId !== part.assetId ||
      asset.storagePath !== part.content ||
      asset.ownerUid !== uid ||
      asset.groupId !== input.groupId ||
      asset.entityType !== "message" ||
      asset.entityId !== input.messageId ||
      asset.sizeBytes !== part.sizeBytes ||
      (part.type === "image" &&
        !/^image\/(jpeg|png|webp)$/.test(asset.mimeType)) ||
      (part.type === "voice" &&
        !/^audio\/(aac|m4a|mp4|mpeg|ogg|wav|webm)$/.test(
          asset.mimeType,
        )) ||
      !["pending", "committed"].includes(asset.status)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "An attachment is not registered for this message.",
      );
    }
  }
}

exports.createStudyGroup = onCall(highAbuseCallableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const name = requireString(request.data?.name, "name", 80);
    const description = optionalString(
      request.data?.description,
      "description",
      1000,
    ) ?? "";
    const groupType = requireString(
      request.data?.groupType,
      "groupType",
      20,
    );
    if (!["Bible", "Topic"].includes(groupType)) {
      throw new RangeError("groupType must be Bible or Topic");
    }

    const topic = optionalString(request.data?.topic, "topic", 200);
    const studyBook = optionalString(
      request.data?.studyBook,
      "studyBook",
      80,
    );
    const totalChapters = request.data?.totalChapters == null
      ? 0
      : requireInteger(request.data.totalChapters, "totalChapters", {
        min: 0,
        max: 366,
      });
    const startDateMillis = request.data?.startDateMillis;
    const endDateMillis = request.data?.endDateMillis;
    const startDate = Number.isInteger(startDateMillis)
      ? Timestamp.fromMillis(startDateMillis)
      : null;
    const endDate = Number.isInteger(endDateMillis)
      ? Timestamp.fromMillis(endDateMillis)
      : null;
    if (startDate && endDate && endDate.toMillis() <= startDate.toMillis()) {
      throw new RangeError("endDate must be after startDate");
    }
    if (!startDate || !endDate) {
      throw new RangeError("startDate and endDate are required");
    }
    if (endDate.toMillis() - startDate.toMillis()
      > 365 * 24 * 60 * 60 * 1000) {
      throw new RangeError("A study cannot run longer than 365 days");
    }
    if (groupType === "Bible" && !studyBook) {
      throw new RangeError("studyBook is required for Bible studies");
    }
    if (groupType === "Topic" && !topic) {
      throw new RangeError("topic is required for topic studies");
    }

    const now = Timestamp.now();
    const groupRef = db.collection("groups").doc();
    const memberRef = groupRef.collection("members").doc(uid);
    const lifecycle = startDate && startDate.toMillis() > now.toMillis()
      ? "scheduled"
      : "active";
    await db.runTransaction(async (transaction) => {
      const [ownedGroups, accountSnapshot] = await Promise.all([
        transaction.get(
          db.collection("groups")
            .where("ownerId", "==", uid)
            .where("lifecycle", "in", ["scheduled", "active"])
            .limit(5),
        ),
        transaction.get(db.doc(`users_private/${uid}`)),
      ]);
      requireAccountPostingAccess(accountSnapshot);
      if (ownedGroups.size >= 5) {
        throw new HttpsError(
          "resource-exhausted",
          "Archive or complete an active study before creating another.",
        );
      }
      await enforceDailyRateLimit(
        transaction,
        uid,
        "create_group",
        now,
      );
      transaction.create(groupRef, {
        schemaVersion: 2,
        ownerId: uid,
        name,
        members: [uid],
        readingProgress: { [uid]: 0 },
        userCompletedChapters: { [uid]: [] },
        unreadCounts: { [uid]: 0 },
        pinnedScripture: "",
        description,
        createdAt: now,
        groupType,
        topic,
        studyBook,
        totalChapters,
        startDate,
        endDate,
        lifecycle,
        extensionCount: 0,
      });
      transaction.create(memberRef, {
        schemaVersion: 2,
        uid,
        role: "owner",
        status: "active",
        joinedAt: now,
        invitedBy: uid,
      });
    });

    return { groupId: groupRef.id };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.createGroupInvite = onCall(highAbuseCallableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const expiresInHours = request.data?.expiresInHours == null
      ? 72
      : requireInteger(request.data.expiresInHours, "expiresInHours", {
        min: 1,
        max: MAX_INVITE_LIFETIME_HOURS,
      });
    const maxUses = request.data?.maxUses == null
      ? 1
      : requireInteger(request.data.maxUses, "maxUses", {
        min: 1,
        max: GROUP_CAPACITY - 1,
      });

    const token = createInviteToken();
    const inviteId = hashInviteToken(token);
    const inviteRef = db.doc(`invites/${inviteId}`);
    const groupRef = db.doc(`groups/${groupId}`);
    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + expiresInHours * 60 * 60 * 1000,
    );

    await db.runTransaction(async (transaction) => {
      const [group, accountSnapshot] = await Promise.all([
        requireGroupOwner(transaction, groupRef, uid),
        transaction.get(db.doc(`users_private/${uid}`)),
      ]);
      requireAccountPostingAccess(accountSnapshot);
      if (group.lifecycle === "archived" || group.lifecycle === "completed") {
        throw new HttpsError(
          "failed-precondition",
          "This study is no longer accepting members.",
        );
      }
      if ((group.members ?? []).length >= GROUP_CAPACITY) {
        throw new HttpsError(
          "resource-exhausted",
          "This study group is full.",
        );
      }

      await enforceInviteRateLimit(transaction, uid, now);
      transaction.create(inviteRef, {
        schemaVersion: 2,
        groupId,
        createdBy: uid,
        createdAt: now,
        expiresAt,
        maxUses,
        useCount: 0,
        revokedAt: null,
      });
    });

    return {
      token,
      joinUrl: `https://braidapp.com/join/${token}`,
      expiresAtMillis: expiresAt.toMillis(),
    };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.sendGroupMessage = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    try {
      const input = normalizeGroupMessageInput(request.data);
      const now = Timestamp.now();
      const groupRef = db.doc(`groups/${input.groupId}`);
      const profileRef = db.doc(`users_public/${uid}`);
      const accountRef = db.doc(`users_private/${uid}`);
      const messageRef = db.doc(
        `groups/${input.groupId}/messages/${input.messageId}`,
      );
      const assetIds = input.parts
        .filter((part) => part.assetId)
        .map((part) => part.assetId);
      if (
        input.attachmentCount > 0 &&
        !(await messageRef.get()).exists
      ) {
        await db.runTransaction((transaction) => enforceDailyRateLimit(
          transaction,
          uid,
          "send_group_attachment",
          now,
          ABUSE_POLICIES.send_group_attachment,
          input.attachmentCount,
        ));
      }

      let alreadyCommitted = false;
      await db.runTransaction(async (transaction) => {
        const [
          groupSnapshot,
          profileSnapshot,
          accountSnapshot,
          messageSnapshot,
          ...assets
        ] =
          await Promise.all([
            transaction.get(groupRef),
            transaction.get(profileRef),
            transaction.get(accountRef),
            transaction.get(messageRef),
            ...assetIds.map(
              (assetId) => transaction.get(
                db.doc(`managed_assets/${assetId}`),
              ),
            ),
          ]);
        if (!groupSnapshot.exists || !profileSnapshot.exists ||
            !accountSnapshot.exists) {
          throw new HttpsError(
            "failed-precondition",
            "Complete your profile and join the study before posting.",
          );
        }
        const group = groupSnapshot.data();
        if (
          !Array.isArray(group.members) ||
          !group.members.includes(uid) ||
          group.lifecycle !== "active"
        ) {
          throw new HttpsError(
            "permission-denied",
            "This study is not accepting messages from this account.",
          );
        }
        if (messageSnapshot.exists) {
          const existing = messageSnapshot.data();
          if (
            existing.senderId !== uid ||
            existing.clientMessageId !== input.clientMessageId ||
            JSON.stringify(existing.parts) !== JSON.stringify(input.parts)
          ) {
            throw new HttpsError(
              "already-exists",
              "That message identifier is already in use.",
            );
          }
          alreadyCommitted = true;
          return;
        }
        validateManagedMessageAssets({ input, assets, uid });
        requireAccountPostingAccess(accountSnapshot);
        await enforceDailyRateLimit(
          transaction,
          uid,
          "send_group_message",
          now,
        );
        const profile = profileSnapshot.data();
        const senderName =
          typeof profile.displayName === "string" &&
          profile.displayName.trim()
            ? profile.displayName.trim().slice(0, 80)
            : "Braid member";
        const senderPhotoUrl =
          typeof profile.photoUrl === "string" && profile.photoUrl
            ? profile.photoUrl.slice(0, 2048)
            : null;
        transaction.create(messageRef, {
          schemaVersion: 2,
          clientMessageId: input.clientMessageId,
          space: input.space,
          senderId: uid,
          senderName,
          ...(senderPhotoUrl ? { senderPhotoUrl } : {}),
          ...(input.replyToMessageId
            ? { replyToMessageId: input.replyToMessageId }
            : {}),
          parts: input.parts,
          clientCreatedAt: now,
          timestamp: now,
          isEdited: false,
          isDeleted: false,
        });
      });
      return { messageId: input.messageId, alreadyCommitted };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.editGroupMessage = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    try {
      const groupId = requireString(request.data?.groupId, "groupId", 128);
      const messageId = requireString(request.data?.messageId, "messageId", 160);
      const now = Timestamp.now();
      const groupRef = db.doc(`groups/${groupId}`);
      const accountRef = db.doc(`users_private/${uid}`);
      const messageRef = db.doc(`groups/${groupId}/messages/${messageId}`);

      await db.runTransaction(async (transaction) => {
        const [groupSnapshot, accountSnapshot, messageSnapshot] =
          await Promise.all([
            transaction.get(groupRef),
            transaction.get(accountRef),
            transaction.get(messageRef),
          ]);
        if (!groupSnapshot.exists || !accountSnapshot.exists ||
            !messageSnapshot.exists) {
          throw new HttpsError("not-found", "Message or study not found.");
        }
        const group = groupSnapshot.data();
        const message = messageSnapshot.data();
        if (!Array.isArray(group.members) || !group.members.includes(uid) ||
            group.lifecycle !== "active") {
          throw new HttpsError(
            "permission-denied",
            "This study is not accepting message edits.",
          );
        }
        if (message.senderId !== uid) {
          throw new HttpsError(
            "permission-denied",
            "Only the message author can edit this message.",
          );
        }
        if (message.isDeleted === true) {
          throw new HttpsError(
            "failed-precondition",
            "Deleted messages cannot be edited.",
          );
        }
        const createdAtMillis = message.timestamp?.toMillis?.();
        if (!Number.isFinite(createdAtMillis) ||
            now.toMillis() - createdAtMillis > 15 * 60 * 1000) {
          throw new HttpsError(
            "failed-precondition",
            "Messages can only be edited for 15 minutes.",
          );
        }
        const input = normalizeGroupMessageInput({
          groupId,
          messageId,
          clientMessageId: message.clientMessageId ?? messageId,
          space: message.space ?? "discussion",
          parts: request.data?.parts,
        });
        const assets = await Promise.all(
          input.parts
            .filter((part) => part.assetId)
            .map((part) => transaction.get(
              db.doc(`managed_assets/${part.assetId}`),
            )),
        );
        validateManagedMessageAssets({ input, assets, uid });
        requireAccountPostingAccess(accountSnapshot);
        if (input.attachmentCount > 0) {
          await enforceDailyRateLimit(
            transaction,
            uid,
            "send_group_attachment",
            now,
            ABUSE_POLICIES.send_group_attachment,
            input.attachmentCount,
          );
        }
        await enforceDailyRateLimit(
          transaction,
          uid,
          "edit_group_message",
          now,
        );
        transaction.update(messageRef, {
          parts: input.parts,
          isEdited: true,
          editedAt: now,
        });
      });
      return { messageId };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.deleteGroupMessage = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const messageId = requireString(request.data?.messageId, "messageId", 160);
    const now = Timestamp.now();
    const groupRef = db.doc(`groups/${groupId}`);
    const messageRef = db.doc(`groups/${groupId}/messages/${messageId}`);
    let alreadyDeleted = false;
    await db.runTransaction(async (transaction) => {
      const [groupSnapshot, messageSnapshot] = await Promise.all([
        transaction.get(groupRef),
        transaction.get(messageRef),
      ]);
      if (!groupSnapshot.exists || !messageSnapshot.exists) {
        throw new HttpsError("not-found", "Message or study not found.");
      }
      const group = groupSnapshot.data();
      const message = messageSnapshot.data();
      if (!Array.isArray(group.members) || !group.members.includes(uid)) {
        throw new HttpsError(
          "permission-denied",
          "Only active study members can remove messages.",
        );
      }
      if (message.senderId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the message author can remove this message.",
        );
      }
      if (message.isDeleted === true) {
        alreadyDeleted = true;
        return;
      }
      transaction.update(messageRef, {
        isDeleted: true,
        parts: [],
        deletedAt: now,
      });
    });
    return { messageId, alreadyDeleted };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.updateStudyGroup = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const name = requireString(request.data?.name, "name", 80);
    const description = optionalString(
      request.data?.description,
      "description",
      1000,
    ) ?? "";
    const pinnedScripture = optionalString(
      request.data?.pinnedScripture,
      "pinnedScripture",
      200,
    ) ?? "";
    const photoUrl = optionalString(
      request.data?.photoUrl,
      "photoUrl",
      2048,
    );
    const groupRef = db.doc(`groups/${groupId}`);
    await db.runTransaction(async (transaction) => {
      const group = await requireGroupOwner(transaction, groupRef, uid);
      if (group.lifecycle === "archived") {
        throw new HttpsError(
          "failed-precondition",
          "Archived studies cannot be edited.",
        );
      }
      transaction.update(groupRef, {
        name,
        description,
        pinnedScripture,
        ...(photoUrl ? { photoUrl } : {}),
        updatedAt: Timestamp.now(),
      });
    });
    return { updated: true };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.redeemGroupInvite = onCall(highAbuseCallableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const token = requireString(request.data?.token, "token", 512, {
      minLength: 32,
    });
    const inviteId = hashInviteToken(token);
    const inviteRef = db.doc(`invites/${inviteId}`);
    const now = Timestamp.now();
    await db.runTransaction((transaction) => enforceDailyRateLimit(
      transaction,
      uid,
      "redeem_group_invite",
      now,
    ));

    const redemption = await db.runTransaction(async (transaction) => {
      const inviteSnapshot = await transaction.get(inviteRef);
      if (!inviteSnapshot.exists) {
        throw new HttpsError(
          "not-found",
          "This invitation is invalid or no longer available.",
        );
      }

      const invite = inviteSnapshot.data();
      const groupRef = db.doc(`groups/${invite.groupId}`);
      const groupSnapshot = await transaction.get(groupRef);
      if (!groupSnapshot.exists) {
        throw new HttpsError("not-found", "Study group not found.");
      }
      const group = groupSnapshot.data();
      const members = Array.isArray(group.members) ? group.members : [];
      const alreadyMember = members.includes(uid);

      if (invite.revokedAt) {
        throw new HttpsError(
          "failed-precondition",
          "This invitation was revoked.",
        );
      }
      if (!invite.expiresAt || invite.expiresAt.toMillis() <= now.toMillis()) {
        throw new HttpsError(
          "deadline-exceeded",
          "This invitation has expired.",
        );
      }
      if (!alreadyMember && invite.useCount >= invite.maxUses) {
        throw new HttpsError(
          "resource-exhausted",
          "This invitation has already been used.",
        );
      }
      if (["completed", "archived"].includes(group.lifecycle)) {
        throw new HttpsError(
          "failed-precondition",
          "This study is no longer accepting members.",
        );
      }
      if (!alreadyMember && members.length >= GROUP_CAPACITY) {
        throw new HttpsError(
          "resource-exhausted",
          "This study group is full.",
        );
      }

      if (alreadyMember) {
        return {
          groupId: invite.groupId,
          joined: false,
          alreadyMember: true,
        };
      }

      const inviterUid = invite.createdBy;
      const memberRef = groupRef.collection("members").doc(uid);
      const inviteeConnectionRef = db.doc(
        `users/${uid}/connections/${inviterUid}`,
      );
      const inviterConnectionRef = db.doc(
        `users/${inviterUid}/connections/${uid}`,
      );
      const inviteeBlockRef = db.doc(`users/${uid}/blocks/${inviterUid}`);
      const inviterBlockRef = db.doc(`users/${inviterUid}/blocks/${uid}`);
      const ownerUid = group.ownerId;
      const inviteeOwnerBlockRef = db.doc(`users/${uid}/blocks/${ownerUid}`);
      const ownerInviteeBlockRef = db.doc(`users/${ownerUid}/blocks/${uid}`);
      const inviteePrivateRef = db.doc(`users_private/${uid}`);
      const inviterPrivateRef = db.doc(`users_private/${inviterUid}`);
      const [
        inviteeConnectionSnapshot,
        inviterConnectionSnapshot,
        inviteeBlockSnapshot,
        inviterBlockSnapshot,
        inviteeOwnerBlockSnapshot,
        ownerInviteeBlockSnapshot,
        inviteePrivateSnapshot,
        inviterPrivateSnapshot,
      ] = await Promise.all([
        transaction.get(inviteeConnectionRef),
        transaction.get(inviterConnectionRef),
        transaction.get(inviteeBlockRef),
        transaction.get(inviterBlockRef),
        transaction.get(inviteeOwnerBlockRef),
        transaction.get(ownerInviteeBlockRef),
        transaction.get(inviteePrivateRef),
        transaction.get(inviterPrivateRef),
      ]);
      if (
        inviteeBlockSnapshot.exists ||
        inviterBlockSnapshot.exists ||
        inviteeOwnerBlockSnapshot.exists ||
        ownerInviteeBlockSnapshot.exists
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This invitation cannot be redeemed.",
        );
      }
      if (!inviteePrivateSnapshot.exists || !inviterPrivateSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Both accounts must complete profile setup before connecting.",
        );
      }
      requireAccountPostingAccess(inviteePrivateSnapshot);
      const inviteeNeedsConnection = !inviteeConnectionSnapshot.exists;
      const inviterNeedsConnection = !inviterConnectionSnapshot.exists;
      const inviteeConnectionCount =
        inviteePrivateSnapshot.data().connectionCount ?? 0;
      const inviterConnectionCount =
        inviterPrivateSnapshot.data().connectionCount ?? 0;
      if ((inviteeNeedsConnection && inviteeConnectionCount >= 500)
        || (inviterNeedsConnection && inviterConnectionCount >= 500)) {
        throw new HttpsError(
          "resource-exhausted",
          "A study-contact limit has been reached.",
        );
      }

      transaction.update(groupRef, {
        members: FieldValue.arrayUnion(uid),
        [`readingProgress.${uid}`]: 0,
        [`userCompletedChapters.${uid}`]: [],
        [`unreadCounts.${uid}`]: 0,
      });
      transaction.create(memberRef, {
        schemaVersion: 2,
        uid,
        role: "member",
        status: "active",
        joinedAt: now,
        invitedBy: inviterUid,
      });
      transaction.set(
        inviteeConnectionRef,
        connectionDocument(uid, inviterUid, now, inviteId),
      );
      transaction.set(
        inviterConnectionRef,
        connectionDocument(inviterUid, uid, now, inviteId),
      );
      if (inviteeNeedsConnection) {
        transaction.update(inviteePrivateRef, {
          connectionCount: FieldValue.increment(1),
          updatedAt: now,
        });
      }
      if (inviterNeedsConnection) {
        transaction.update(inviterPrivateRef, {
          connectionCount: FieldValue.increment(1),
          updatedAt: now,
        });
      }
      transaction.update(inviteRef, {
        useCount: FieldValue.increment(1),
        lastUsedAt: now,
      });

      return {
        groupId: invite.groupId,
        joined: true,
        alreadyMember: false,
        inviterUid,
      };
    });
    if (redemption.joined && redemption.inviterUid) {
      await backfillConnectionInsights(
        uid,
        redemption.inviterUid,
        inviteId,
      );
    }
    delete redemption.inviterUid;
    return redemption;
  } catch (error) {
    throw invalidArgument(error);
  }
});

async function backfillConnectionInsights(firstUid, secondUid, sourceId) {
  const now = Timestamp.now();
  const [firstInsights, secondInsights] = await Promise.all([
    db.collection("insights")
      .where("authorUid", "==", firstUid)
      .where("status", "==", "active")
      .orderBy("expiresAt", "desc")
      .limit(20)
      .get(),
    db.collection("insights")
      .where("authorUid", "==", secondUid)
      .where("status", "==", "active")
      .orderBy("expiresAt", "desc")
      .limit(20)
      .get(),
  ]);
  const batch = db.batch();
  for (const document of firstInsights.docs) {
    const insight = document.data();
    if (insight.expiresAt?.toMillis?.() > now.toMillis()) {
      batch.set(
        db.doc(`users/${secondUid}/insight_feed/${document.id}`),
        insightFeedDocument(document, insight, sourceId),
      );
    }
  }
  for (const document of secondInsights.docs) {
    const insight = document.data();
    if (insight.expiresAt?.toMillis?.() > now.toMillis()) {
      batch.set(
        db.doc(`users/${firstUid}/insight_feed/${document.id}`),
        insightFeedDocument(document, insight, sourceId),
      );
    }
  }
  await batch.commit();
}

function insightFeedDocument(document, insight, sourceId = "connection") {
  return {
    schemaVersion: 2,
    insightId: document.id,
    authorUid: insight.authorUid,
    authorName: insight.authorName,
    ...(insight.authorPhotoUrl ? { authorPhotoUrl: insight.authorPhotoUrl } : {}),
    title: insight.title,
    body: insight.body,
    themeId: insight.themeId,
    audience: insight.audience,
    status: insight.status,
    createdAt: insight.createdAt ?? Timestamp.now(),
    publishedAt: insight.createdAt ?? Timestamp.now(),
    updatedAt: insight.updatedAt ?? Timestamp.now(),
    expiresAt: insight.expiresAt,
    sourceId,
  };
}

exports.publishInsight = onCall(highAbuseCallableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const { title, body, themeId } = normalizeInsightInput(request.data);
    const requestedInsightId = request.data?.insightId == null
      ? null
      : requireString(request.data.insightId, "insightId", 160);
    const insightId = requestedInsightId ?? db.collection("insights").doc().id;
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(insightId)) {
      throw new RangeError("insightId is invalid.");
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + 3 * 24 * 60 * 60 * 1000,
    );
    const insightRef = db.doc(`insights/${insightId}`);
    const profileRef = db.doc(`users_public/${uid}`);
    const accountRef = db.doc(`users_private/${uid}`);
    const existingBeforeAudience = await insightRef.get();
    if (existingBeforeAudience.exists) {
      const existing = existingBeforeAudience.data();
      if (
        existing.authorUid !== uid ||
        existing.title !== title ||
        existing.body !== body ||
        existing.themeId !== themeId
      ) {
        throw new HttpsError(
          "already-exists",
          "That Insight identifier is already in use.",
        );
      }
      return {
        insightId,
        expiresAtMillis: existing.expiresAt?.toMillis?.() ?? 0,
        alreadyCommitted: true,
      };
    }
    const connectionCountSnapshot = await db
      .collection(`users/${uid}/connections`)
      .where("status", "==", "accepted")
      .limit(501)
      .get();
    if (connectionCountSnapshot.size > 500) {
      throw new HttpsError(
        "resource-exhausted",
        "The reflection audience is too large to publish safely.",
      );
    }

    let alreadyCommitted = false;
    let committedExpiresAtMillis = expiresAt.toMillis();
    await db.runTransaction(async (transaction) => {
      const [profileSnapshot, accountSnapshot, existingSnapshot] =
        await Promise.all([
          transaction.get(profileRef),
          transaction.get(accountRef),
          transaction.get(insightRef),
        ]);
      if (existingSnapshot.exists) {
        const existing = existingSnapshot.data();
        if (
          existing.authorUid !== uid ||
          existing.title !== title ||
          existing.body !== body ||
          existing.themeId !== themeId
        ) {
          throw new HttpsError(
            "already-exists",
            "That Insight identifier is already in use.",
          );
        }
        alreadyCommitted = true;
        committedExpiresAtMillis = existing.expiresAt?.toMillis?.()
          ?? committedExpiresAtMillis;
        return;
      }
      if (!profileSnapshot.exists || !accountSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Complete your profile before sharing an Insight.",
        );
      }
      requireAccountPostingAccess(accountSnapshot);
      await enforceDailyRateLimit(
        transaction,
        uid,
        "publish_insight",
        now,
      );
      await enforceDailyRateLimit(
        transaction,
        uid,
        "insight_fanout",
        now,
        ABUSE_POLICIES.insight_fanout,
        connectionCountSnapshot.size + 1,
      );
      const profile = profileSnapshot.data();
      const authorName = typeof profile.displayName === "string"
        && profile.displayName.trim()
        ? profile.displayName.trim().slice(0, 80)
        : "Braid member";
      const authorPhotoUrl = typeof profile.photoUrl === "string"
        && profile.photoUrl
        ? profile.photoUrl.slice(0, 2048)
        : null;

      transaction.create(insightRef, {
        schemaVersion: 2,
        authorUid: uid,
        authorName,
        ...(authorPhotoUrl ? { authorPhotoUrl } : {}),
        title,
        body,
        themeId,
        audience: "contacts",
        status: "active",
        createdAt: now,
        updatedAt: now,
        expiresAt,
      });
    });
    return {
      insightId: insightRef.id,
      expiresAtMillis: committedExpiresAtMillis,
      alreadyCommitted,
    };
  } catch (error) {
    throw invalidArgument(error);
  }
});

async function requireVisibleInsight(
  transaction,
  insightRef,
  uid,
  now,
) {
  const insightSnapshot = await transaction.get(insightRef);
  if (!insightSnapshot.exists) {
    throw new HttpsError("not-found", "Reflection not found.");
  }
  const insight = insightSnapshot.data();
  if (insight.authorUid === uid) return insight;
  const [connection, viewerBlock, authorBlock] = await Promise.all([
    transaction.get(
      db.doc(`users/${insight.authorUid}/connections/${uid}`),
    ),
    transaction.get(db.doc(`users/${uid}/blocks/${insight.authorUid}`)),
    transaction.get(db.doc(`users/${insight.authorUid}/blocks/${uid}`)),
  ]);
  if (
    insight.status !== "active" ||
    insight.expiresAt?.toMillis?.() <= now.toMillis() ||
    !connection.exists ||
    connection.data().status !== "accepted" ||
    viewerBlock.exists ||
    authorBlock.exists
  ) {
    throw new HttpsError(
      "permission-denied",
      "This reflection is not visible to this account.",
    );
  }
  return insight;
}

exports.createInsightComment = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    try {
      const insightId = requireString(request.data?.insightId, "insightId", 160);
      const commentId = requireString(request.data?.commentId, "commentId", 160);
      const body = requireString(request.data?.body, "body", 4000);
      const replyToId = optionalString(
        request.data?.replyToId,
        "replyToId",
        160,
      );
      const now = Timestamp.now();
      const insightRef = db.doc(`insights/${insightId}`);
      const commentRef = insightRef.collection("comments").doc(commentId);
      const profileRef = db.doc(`users_public/${uid}`);
      const accountRef = db.doc(`users_private/${uid}`);
      await db.runTransaction(async (transaction) => {
        const [
          insight,
          profileSnapshot,
          accountSnapshot,
          existingComment,
          parentSnapshot,
        ] =
          await Promise.all([
            requireVisibleInsight(transaction, insightRef, uid, now),
            transaction.get(profileRef),
            transaction.get(accountRef),
            transaction.get(commentRef),
            replyToId
              ? transaction.get(
                insightRef.collection("comments").doc(replyToId),
              )
              : Promise.resolve(null),
          ]);
        if (existingComment.exists) {
          if (
            existingComment.data().authorUid === uid &&
            existingComment.data().body === body
          ) {
            return;
          }
          throw new HttpsError(
            "already-exists",
            "That comment identifier is already in use.",
          );
        }
        if (!profileSnapshot.exists || !accountSnapshot.exists ||
            (replyToId && !parentSnapshot?.exists)) {
          throw new HttpsError(
            "failed-precondition",
            "The profile or reply target is unavailable.",
          );
        }
        requireAccountPostingAccess(accountSnapshot);
        await enforceDailyRateLimit(
          transaction,
          uid,
          "create_insight_comment",
          now,
        );
        const profile = profileSnapshot.data();
        transaction.create(commentRef, {
          schemaVersion: 2,
          insightId,
          authorUid: uid,
          authorName: boundedNotificationText(
            profile.displayName,
            "Braid member",
          ),
          ...(typeof profile.photoUrl === "string" && profile.photoUrl
            ? { authorPhotoUrl: profile.photoUrl.slice(0, 2048) }
            : {}),
          body,
          ...(replyToId ? { replyToId } : {}),
          createdAt: now,
        });
        void insight;
      });
      return { commentId };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.setInsightReaction = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    try {
      const insightId = requireString(request.data?.insightId, "insightId", 160);
      const commentId = optionalString(
        request.data?.commentId,
        "commentId",
        160,
      );
      if (typeof request.data?.active !== "boolean") {
        throw new TypeError("active must be a boolean");
      }
      const now = Timestamp.now();
      const insightRef = db.doc(`insights/${insightId}`);
      const parentRef = commentId
        ? insightRef.collection("comments").doc(commentId)
        : insightRef;
      const reactionRef = parentRef.collection("reactions").doc(uid);
      const accountRef = db.doc(`users_private/${uid}`);
      await db.runTransaction(async (transaction) => {
        const [accountSnapshot, , parentSnapshot] = await Promise.all([
          transaction.get(accountRef),
          requireVisibleInsight(transaction, insightRef, uid, now),
          commentId ? transaction.get(parentRef) : Promise.resolve(null),
        ]);
        requireAccountPostingAccess(accountSnapshot);
        if (commentId && !parentSnapshot?.exists) {
          throw new HttpsError("not-found", "Comment not found.");
        }
        await enforceDailyRateLimit(
          transaction,
          uid,
          "set_reaction",
          now,
        );
        if (request.data.active) {
          transaction.set(reactionRef, {
            uid,
            reaction: "helpful",
            createdAt: now,
          });
        } else {
          transaction.delete(reactionRef);
        }
      });
      return { active: request.data.active };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.submitReport = onCall(highAbuseCallableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const {
      targetType,
      targetId,
      groupId,
      insightId,
      reason,
      details,
    } = normalizeReportInput(request.data);
    const now = Timestamp.now();
    const reportRef = db.collection("reports").doc();
    const accountRef = db.doc(`users_private/${uid}`);
    await db.runTransaction(async (transaction) => {
      const accountSnapshot = await transaction.get(accountRef);
      requireAccountPostingAccess(accountSnapshot);
      const targetPath = reportTargetPath({
        targetType,
        targetId,
        groupId,
        insightId,
      });
      const targetRef = db.doc(targetPath);
      let target;
      if (targetType === "insight") {
        target = await requireVisibleInsight(
          transaction,
          targetRef,
          uid,
          now,
        );
      } else if (targetType === "comment") {
        const commentInsightRef = db.doc(`insights/${insightId}`);
        await requireVisibleInsight(transaction, commentInsightRef, uid, now);
        const targetSnapshot = await transaction.get(targetRef);
        if (!targetSnapshot.exists) {
          throw new HttpsError("not-found", "Report target not found.");
        }
        target = targetSnapshot.data();
      } else if (targetType === "message") {
        const [targetSnapshot, groupSnapshot] = await Promise.all([
          transaction.get(targetRef),
          transaction.get(db.doc(`groups/${groupId}`)),
        ]);
        if (
          !targetSnapshot.exists ||
          !groupSnapshot.exists ||
          !Array.isArray(groupSnapshot.data().members) ||
          !groupSnapshot.data().members.includes(uid)
        ) {
          throw new HttpsError(
            "permission-denied",
            "The reported message is not visible to this account.",
          );
        }
        target = targetSnapshot.data();
      } else {
        const targetSnapshot = await transaction.get(targetRef);
        if (!targetSnapshot.exists) {
          throw new HttpsError("not-found", "Report target not found.");
        }
        target = targetSnapshot.data();
        if (
          targetType === "group" &&
          (!Array.isArray(target.members) || !target.members.includes(uid))
        ) {
          throw new HttpsError(
            "permission-denied",
            "The reported study is not visible to this account.",
          );
        }
      }
      await enforceDailyRateLimit(
        transaction,
        uid,
        "submit_report",
        now,
      );
      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterUid: uid,
        targetType,
        targetId,
        ...(groupId ? { groupId } : {}),
        ...(insightId ? { insightId } : {}),
        reason,
        ...(details ? { details } : {}),
        evidence: {
          capturedAt: now,
          ownerUid: target.authorUid ?? target.senderId ?? target.uid
            ?? target.ownerId ?? null,
          status: target.status ?? target.lifecycle ?? null,
          excerpt: boundedNotificationText(
            target.body ?? target.parts?.[0]?.content ?? target.displayName
              ?? target.name,
            "No text evidence available.",
          ),
        },
        status: "open",
        createdAt: now,
      });
    });
    return { reportId: reportRef.id };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.moderateReport = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const operatorUid = authenticatedUid(request);
    try {
      const decision = normalizeModerationDecision(request.data);
      const now = Timestamp.now();
      const reportRef = db.doc(`reports/${decision.reportId}`);
      const operatorRef = db.doc(`moderation_operators/${operatorUid}`);
      const auditRef = db.doc(`moderation_audit/${decision.actionId}`);
      let idempotentReplay = false;
      await db.runTransaction(async (transaction) => {
        const [operatorSnapshot, reportSnapshot, auditSnapshot] =
          await Promise.all([
            transaction.get(operatorRef),
            transaction.get(reportRef),
            transaction.get(auditRef),
          ]);
        if (
          !operatorSnapshot.exists ||
          operatorSnapshot.data().status !== "active"
        ) {
          throw new HttpsError(
            "permission-denied",
            "This operator assignment is not active.",
          );
        }
        const operatorRole = operatorSnapshot.data().role;
        const capabilities = moderationCapabilities({
          moderationRole: operatorRole,
        });
        if (!capabilities.includes(decision.action)) {
          throw new HttpsError(
            "permission-denied",
            "This operator role cannot perform that action.",
          );
        }
        if (auditSnapshot.exists) {
          const existing = auditSnapshot.data();
          if (
            existing.operatorUid === operatorUid &&
            existing.reportId === decision.reportId &&
            existing.action === decision.action
          ) {
            idempotentReplay = true;
            return;
          }
          throw new HttpsError(
            "already-exists",
            "That moderation action identifier is already in use.",
          );
        }
        if (!reportSnapshot.exists) {
          throw new HttpsError("not-found", "Report not found.");
        }
        const report = reportSnapshot.data();
        if (report.status === "resolved") {
          throw new HttpsError(
            "failed-precondition",
            "This report has already been resolved.",
          );
        }
        const targetPath = reportTargetPath(report);
        const targetRef = db.doc(targetPath);
        const targetSnapshot = await transaction.get(targetRef);
        if (
          decision.action !== "dismiss_report" &&
          decision.action !== "restore_account" &&
          !targetSnapshot.exists
        ) {
          throw new HttpsError("not-found", "Moderation target not found.");
        }
        const accountUid = report.evidence?.ownerUid ??
          (report.targetType === "user" ? report.targetId : null);
        const accountRef = accountUid
          ? db.doc(`users_private/${accountUid}`)
          : null;
        const accountSnapshot = accountRef
          ? await transaction.get(accountRef)
          : null;
        const accountStatusBefore = accountSnapshot?.exists
          ? accountSnapshot.data().accountStatus ?? "active"
          : null;

        if (decision.action === "remove_content") {
          if (report.targetType === "insight") {
            transaction.update(targetRef, {
              status: "removed",
              moderatedAt: now,
              moderationAuditId: auditRef.id,
            });
          } else if (report.targetType === "message") {
            transaction.update(targetRef, {
              parts: [],
              isDeleted: true,
              deletedAt: now,
              moderatedAt: now,
              moderationAuditId: auditRef.id,
            });
          } else if (report.targetType === "group") {
            transaction.update(targetRef, {
              lifecycle: "archived",
              archivedAt: now,
              moderatedAt: now,
              moderationAuditId: auditRef.id,
            });
          } else if (report.targetType === "comment") {
            transaction.update(targetRef, {
              body: "This comment was removed by moderation.",
              isRemoved: true,
              removedAt: now,
              updatedAt: now,
              moderatedAt: now,
              moderationAuditId: auditRef.id,
            });
          } else {
            throw new HttpsError(
              "failed-precondition",
              "This target does not support content removal.",
            );
          }
        }
        if ([
          "restrict_account",
          "suspend_account",
          "restore_account",
        ].includes(decision.action)) {
          if (!accountRef || !accountSnapshot?.exists) {
            throw new HttpsError(
              "failed-precondition",
              "The target account record is unavailable.",
            );
          }
          const accountStatus = decision.action === "restore_account"
            ? "active"
            : decision.action === "suspend_account"
              ? "suspended"
              : "restricted";
          transaction.update(accountRef, {
            accountStatus,
            moderationAuditId: auditRef.id,
            moderationUpdatedAt: now,
          });
        }
        transaction.create(auditRef, {
          ...buildModerationAuditRecord({
            operatorUid,
            operatorRole,
            decision,
            report: {
              ...report,
              ...(accountStatusBefore
                ? { accountStatusBefore }
                : {}),
            },
            now,
          }),
          retentionExpiresAt: Timestamp.fromMillis(
            now.toMillis() + 730 * 24 * 60 * 60 * 1000,
          ),
        });
        transaction.update(reportRef, {
          status: "resolved",
          taxonomy: decision.taxonomy,
          resolution: decision.action,
          resolvedAt: now,
          resolvedBy: operatorUid,
          moderationAuditId: auditRef.id,
          retentionExpiresAt: Timestamp.fromMillis(
            now.toMillis() + 180 * 24 * 60 * 60 * 1000,
          ),
        });
      });
      return {
        auditId: auditRef.id,
        status: "resolved",
        idempotentReplay,
      };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.submitModerationAppeal = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    try {
      const auditId = requireString(request.data?.auditId, "auditId", 160);
      const statement = requireString(
        request.data?.statement,
        "statement",
        4_000,
        { minLength: 20 },
      );
      const now = Timestamp.now();
      const auditRef = db.doc(`moderation_audit/${auditId}`);
      const appealRef = db.doc(`moderation_appeals/${auditId}_${uid}`);
      await db.runTransaction(async (transaction) => {
        const [auditSnapshot, appealSnapshot] = await Promise.all([
          transaction.get(auditRef),
          transaction.get(appealRef),
        ]);
        if (!auditSnapshot.exists) {
          throw new HttpsError("not-found", "Moderation action not found.");
        }
        const audit = auditSnapshot.data();
        if (
          audit.reportSnapshot?.ownerUid !== uid &&
          audit.reportSnapshot?.targetId !== uid
        ) {
          throw new HttpsError(
            "permission-denied",
            "This moderation action does not belong to this account.",
          );
        }
        if (appealSnapshot.exists) {
          throw new HttpsError(
            "already-exists",
            "An appeal is already open for this action.",
          );
        }
        transaction.create(appealRef, {
          schemaVersion: 1,
          auditId,
          appellantUid: uid,
          statement,
          status: "open",
          createdAt: now,
        });
      });
      return { appealId: appealRef.id, status: "open" };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.reviewModerationAppeal = onCall(
  highAbuseCallableOptions,
  async (request) => {
    const reviewerUid = authenticatedUid(request);
    try {
      const appealId = requireString(request.data?.appealId, "appealId", 321);
      const reviewId = requireString(request.data?.reviewId, "reviewId", 160);
      const outcome = requireString(request.data?.outcome, "outcome", 20);
      const rationale = requireString(
        request.data?.rationale,
        "rationale",
        2_000,
        { minLength: 10 },
      );
      if (!["upheld", "overturned"].includes(outcome)) {
        throw new RangeError("outcome is unsupported");
      }
      const appealRef = db.doc(`moderation_appeals/${appealId}`);
      const operatorRef = db.doc(`moderation_operators/${reviewerUid}`);
      const reviewRef = db.doc(`moderation_appeal_audit/${reviewId}`);
      const now = Timestamp.now();
      await db.runTransaction(async (transaction) => {
        const [operatorSnapshot, appealSnapshot, reviewSnapshot] =
          await Promise.all([
            transaction.get(operatorRef),
            transaction.get(appealRef),
            transaction.get(reviewRef),
          ]);
        if (
          !operatorSnapshot.exists ||
          operatorSnapshot.data().status !== "active" ||
          !moderationCapabilities({
            moderationRole: operatorSnapshot.data().role,
          }).includes("suspend_account")
        ) {
          throw new HttpsError(
            "permission-denied",
            "An active trust and safety reviewer is required.",
          );
        }
        if (reviewSnapshot.exists) {
          const existing = reviewSnapshot.data();
          if (
            existing.reviewerUid === reviewerUid &&
            existing.appealId === appealId &&
            existing.outcome === outcome
          ) {
            return;
          }
          throw new HttpsError(
            "already-exists",
            "That appeal review identifier is already in use.",
          );
        }
        if (!appealSnapshot.exists || appealSnapshot.data().status !== "open") {
          throw new HttpsError(
            "failed-precondition",
            "This appeal is not open.",
          );
        }
        const appeal = appealSnapshot.data();
        const actionSnapshot = await transaction.get(
          db.doc(`moderation_audit/${appeal.auditId}`),
        );
        if (!actionSnapshot.exists) {
          throw new HttpsError("not-found", "Original action not found.");
        }
        if (actionSnapshot.data().operatorUid === reviewerUid) {
          throw new HttpsError(
            "permission-denied",
            "Appeals require an independent reviewer.",
          );
        }
        transaction.create(reviewRef, {
          schemaVersion: 1,
          reviewId,
          appealId,
          originalAuditId: appeal.auditId,
          reviewerUid,
          reviewerRole: operatorSnapshot.data().role,
          outcome,
          rationale,
          createdAt: now,
          retentionExpiresAt: Timestamp.fromMillis(
            now.toMillis() + 730 * 24 * 60 * 60 * 1000,
          ),
        });
        transaction.update(appealRef, {
          status: outcome,
          reviewedAt: now,
          reviewedBy: reviewerUid,
          reviewAuditId: reviewId,
          retentionExpiresAt: Timestamp.fromMillis(
            now.toMillis() + 180 * 24 * 60 * 60 * 1000,
          ),
        });
        if (
          outcome === "overturned" &&
          [
            "restrict_account",
            "suspend_account",
            "restore_account",
          ].includes(actionSnapshot.data().action)
        ) {
          const priorStatus = actionSnapshot.data().reportSnapshot
            ?.accountStatusBefore ?? "active";
          transaction.update(db.doc(`users_private/${appeal.appellantUid}`), {
            accountStatus: priorStatus,
            moderationUpdatedAt: now,
            moderationAuditId: reviewId,
          });
        }
      });
      return { reviewId, outcome };
    } catch (error) {
      throw invalidArgument(error);
    }
  },
);

exports.syncInsightFeed = onDocumentWritten(
  {
    document: "insights/{insightId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const insightId = event.params.insightId;
    const insight = after?.exists ? after.data() : before?.data();
    if (!insight?.authorUid) return;

    const connectionSnapshot = await db
      .collection(`users/${insight.authorUid}/connections`)
      .where("status", "==", "accepted")
      .limit(500)
      .get();
    const recipientIds = new Set([
      insight.authorUid,
      ...connectionSnapshot.docs.map((document) => document.id),
    ]);
    const active = after?.exists
      && insight.status === "active"
      && insight.expiresAt?.toMillis?.() > Date.now();
    const references = [...recipientIds].map(
      (uid) => db.doc(`users/${uid}/insight_feed/${insightId}`),
    );

    for (let offset = 0; offset < references.length; offset += 400) {
      const batch = db.batch();
      const slice = references.slice(offset, offset + 400);
      for (const reference of slice) {
        if (active) {
          batch.set(
            reference,
            insightFeedDocument(after, insight),
            { merge: true },
          );
        } else {
          batch.delete(reference);
        }
      }
      await batch.commit();
    }

    if (!before?.exists && active) {
      const authorSnapshot = await db
        .doc(`users_public/${insight.authorUid}`)
        .get();
      const authorName = boundedNotificationText(
        authorSnapshot.data()?.displayName,
        "A study contact",
      );
      await sendAudienceNotification({
        recipientIds: [...recipientIds].filter(
          (uid) => uid !== insight.authorUid,
        ),
        type: "new_insight",
        title: `${authorName} shared a reflection`,
        fullBody: boundedNotificationText(
          insight.title || insight.body,
          "Open Braid to read it.",
        ),
        privateBody: "Open Braid to view this reflection.",
        data: { insightId },
        preferenceField: "insightNotifications",
        channelId: "braid_insights",
      });
    }
  },
);

exports.revokeGroupInvite = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const token = requireString(request.data?.token, "token", 512, {
      minLength: 32,
    });
    const inviteId = hashInviteToken(token);
    const inviteRef = db.doc(`invites/${inviteId}`);
    const now = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const inviteSnapshot = await transaction.get(inviteRef);
      if (!inviteSnapshot.exists) {
        throw new HttpsError("not-found", "Invitation not found.");
      }
      const invite = inviteSnapshot.data();
      if (invite.createdBy !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the invitation creator can revoke it.",
        );
      }
      transaction.update(inviteRef, { revokedAt: now });
    });

    return { revoked: true };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.transferGroupOwnership = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const newOwnerUid = requireString(
      request.data?.newOwnerUid,
      "newOwnerUid",
      128,
    );
    if (newOwnerUid === uid) {
      return { transferred: false, ownerId: uid };
    }

    const groupRef = db.doc(`groups/${groupId}`);
    const currentOwnerRef = groupRef.collection("members").doc(uid);
    const newOwnerRef = groupRef.collection("members").doc(newOwnerUid);

    await db.runTransaction(async (transaction) => {
      const [group, newOwnerSnapshot] = await Promise.all([
        requireGroupOwner(transaction, groupRef, uid),
        transaction.get(newOwnerRef),
      ]);
      if (!(group.members ?? []).includes(newOwnerUid)
        || !newOwnerSnapshot.exists
        || newOwnerSnapshot.data().status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "The new owner must be an active group member.",
        );
      }

      transaction.update(groupRef, { ownerId: newOwnerUid });
      transaction.set(currentOwnerRef, { role: "member" }, { merge: true });
      transaction.set(newOwnerRef, { role: "owner" }, { merge: true });
    });

    return { transferred: true, ownerId: newOwnerUid };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.removeGroupMember = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const memberUid = requireString(
      request.data?.memberUid,
      "memberUid",
      128,
    );
    if (memberUid === uid) {
      throw new HttpsError(
        "failed-precondition",
        "Use the leave-group action for your own membership.",
      );
    }

    const groupRef = db.doc(`groups/${groupId}`);
    const memberRef = groupRef.collection("members").doc(memberUid);
    const now = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const group = await requireGroupOwner(transaction, groupRef, uid);
      if (!(group.members ?? []).includes(memberUid)) {
        return;
      }

      transaction.update(groupRef, {
        members: FieldValue.arrayRemove(memberUid),
        [`readingProgress.${memberUid}`]: FieldValue.delete(),
        [`userCompletedChapters.${memberUid}`]: FieldValue.delete(),
        [`unreadCounts.${memberUid}`]: FieldValue.delete(),
      });
      transaction.set(
        memberRef,
        {
          status: "removed",
          removedAt: now,
          removedBy: uid,
        },
        { merge: true },
      );
    });

    return { removed: true };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.leaveGroup = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const groupRef = db.doc(`groups/${groupId}`);
    const memberRef = groupRef.collection("members").doc(uid);
    const stateRef = db.doc(`users/${uid}/group_state/${groupId}`);
    const now = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const groupSnapshot = await transaction.get(groupRef);
      if (!groupSnapshot.exists) {
        throw new HttpsError("not-found", "Study group not found.");
      }

      const group = groupSnapshot.data();
      const members = Array.isArray(group.members) ? group.members : [];
      if (!members.includes(uid)) return;
      if (group.ownerId === uid) {
        throw new HttpsError(
          "failed-precondition",
          members.length > 1
            ? "Transfer ownership before leaving this study."
            : "Archive or delete your study before leaving it.",
        );
      }

      transaction.update(groupRef, {
        members: FieldValue.arrayRemove(uid),
        [`readingProgress.${uid}`]: FieldValue.delete(),
        [`userCompletedChapters.${uid}`]: FieldValue.delete(),
        [`unreadCounts.${uid}`]: FieldValue.delete(),
      });
      transaction.set(
        memberRef,
        {
          status: "left",
          leftAt: now,
        },
        { merge: true },
      );
      transaction.set(
        stateRef,
        {
          groupId,
          clearedBefore: now,
          updatedAt: now,
        },
        { merge: true },
      );
    });

    return { left: true };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.extendGroupDuration = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const days = requireInteger(request.data?.days, "days", {
      min: 1,
      max: 30,
    });
    if (![7, 14, 30].includes(days)) {
      throw new RangeError("days must be 7, 14, or 30");
    }

    const groupRef = db.doc(`groups/${groupId}`);
    const now = Timestamp.now();
    let newEndDate;

    await db.runTransaction(async (transaction) => {
      const group = await requireGroupOwner(transaction, groupRef, uid);
      if (group.lifecycle === "archived") {
        throw new HttpsError(
          "failed-precondition",
          "Archived studies cannot be extended.",
        );
      }
      const extensionCount = group.extensionCount ?? 0;
      if (extensionCount >= 3) {
        throw new HttpsError(
          "failed-precondition",
          "This study has reached its extension limit.",
        );
      }

      const currentEndMillis = group.endDate?.toMillis?.() ?? now.toMillis();
      newEndDate = Timestamp.fromMillis(
        Math.max(currentEndMillis, now.toMillis())
          + days * 24 * 60 * 60 * 1000,
      );
      transaction.update(groupRef, {
        endDate: newEndDate,
        ...(group.lifecycle === "completed"
          ? {
            lifecycle: "active",
            reactivatedAt: now,
          }
          : {}),
        extensionCount: FieldValue.increment(1),
      });
    });

    return {
      extended: true,
      endDateMillis: newEndDate.toMillis(),
    };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.archiveStudyGroup = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const groupId = requireString(request.data?.groupId, "groupId", 128);
    const groupRef = db.doc(`groups/${groupId}`);
    await db.runTransaction(async (transaction) => {
      const group = await requireGroupOwner(transaction, groupRef, uid);
      if (group.lifecycle === "archived") return;
      transaction.update(groupRef, {
        lifecycle: "archived",
        archivedAt: Timestamp.now(),
      });
    });
    return { archived: true };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.deleteCurrentAccount = onCall(
  callableOptions,
  async (request) => {
    const uid = authenticatedUid(request);
    const authenticatedAtSeconds = request.auth?.token?.auth_time;
    if (!Number.isInteger(authenticatedAtSeconds)
      || Date.now() - authenticatedAtSeconds * 1000 > 10 * 60 * 1000) {
      throw new HttpsError(
        "failed-precondition",
        "Sign out, sign back in, then retry account deletion.",
      );
    }

    const jobRef = db.doc(`account_deletion_jobs/${uid}`);
    const deletionJob = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(jobRef);
      if (existing.exists) {
        const job = existing.data();
        if (job.status === "complete") return job;
        transaction.update(jobRef, {
          status: "queued",
          lastError: FieldValue.delete(),
          retryAfter: FieldValue.delete(),
          updatedAt: Timestamp.now(),
        });
        return { ...job, status: "queued" };
      }
      const now = Timestamp.now();
      const job = {
        schemaVersion: 1,
        uid,
        status: "queued",
        phase: "preflight",
        completedPages: 0,
        requestedAt: now,
        updatedAt: now,
      };
      transaction.set(jobRef, job);
      transaction.set(db.doc(`users_private/${uid}`), {
        deletionState: "requested",
        updatedAt: now,
      }, { merge: true });
      return job;
    });
    return {
      deleted: deletionJob.status === "complete",
      status: deletionJob.status,
      phase: deletionJob.phase,
    };
  },
);

async function runAccountDeletionJob(uid) {
  const jobRef = db.doc(`account_deletion_jobs/${uid}`);
  const lease = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists || snapshot.data().status === "complete") return null;
    const job = snapshot.data();
    const nowMillis = Date.now();
    if (job.status === "running" &&
        job.leaseUntil?.toMillis?.() > nowMillis) {
      return null;
    }
    transaction.update(jobRef, {
      status: "running",
      leaseUntil: Timestamp.fromMillis(nowMillis + 5 * 60 * 1000),
      attempts: FieldValue.increment(1),
      updatedAt: Timestamp.now(),
    });
    return job;
  });
  if (!lease) return;

  try {
    const result = await processDeletionStep({
      job: lease,
      handlers: createAccountDeletionHandlers({
        uid,
        db,
        auth: admin.auth(),
        bucket: admin.storage().bucket(),
        FieldValue,
        FieldPath: admin.firestore.FieldPath,
        Timestamp,
        job: lease,
      }),
    });
    await jobRef.update({
      status: result.complete ? "complete" : "queued",
      phase: result.phase,
      completedPages: result.completedPages,
      processedInLastPage: result.processedInLastPage,
      cursor: result.cursor == null
        ? FieldValue.delete()
        : result.cursor,
      leaseUntil: FieldValue.delete(),
      lastError: FieldValue.delete(),
      updatedAt: Timestamp.now(),
      ...(result.complete ? { completedAt: Timestamp.now() } : {}),
    });
  } catch (error) {
    const blocked = error?.code === "failed-precondition";
    await jobRef.update({
      status: blocked ? "blocked" : "retrying",
      leaseUntil: FieldValue.delete(),
      lastError: blocked
        ? error.message
        : "Deletion paused after a temporary failure.",
      retryAfter: blocked
        ? FieldValue.delete()
        : Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
      updatedAt: Timestamp.now(),
    });
    logger.error("Account deletion step failed", {
      uid,
      phase: lease.phase,
      blocked,
      error,
    });
  }
}

exports.processAccountDeletionJob = onDocumentWritten(
  {
    document: "account_deletion_jobs/{uid}",
    region: "us-central1",
  },
  async (event) => {
    const job = event.data?.after.data();
    if (!job || job.status !== "queued") return;
    await runAccountDeletionJob(event.params.uid);
  },
);

exports.resumeAccountDeletionJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "us-central1",
    timeZone: "Etc/UTC",
    retryCount: 3,
  },
  async () => {
    const snapshot = await db.collection("account_deletion_jobs")
      .where("status", "in", ["queued", "running", "retrying"])
      .limit(20)
      .get();
    await mapInChunks(snapshot.docs, 5, async (document) => {
      const job = document.data();
      if (job.status === "retrying" &&
          job.retryAfter?.toMillis?.() > Date.now()) return;
      await runAccountDeletionJob(document.id);
    });
  },
);

exports.advanceGroupLifecycle = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "us-central1",
    timeZone: "Etc/UTC",
    retryCount: 3,
  },
  async () => {
    const now = Timestamp.now();
    const scheduledQuery = () => db.collection("groups")
      .where("lifecycle", "==", "scheduled")
      .where("startDate", "<=", now);
    const activeQuery = () => db.collection("groups")
      .where("lifecycle", "==", "active")
      .where("endDate", "<=", now);
    const metrics = await drainPagedJob({
      // Updating lifecycle removes every successful document from these
      // queries, so restarting from the head is a mutation-derived cursor.
      // Inserts before/after a previous page therefore cannot be skipped.
      loadPage: async ({ limit }) => {
        const perStateLimit = Math.max(1, Math.floor(limit / 2));
        const [scheduled, active] = await Promise.all([
          scheduledQuery().orderBy("startDate").limit(perStateLimit).get(),
          activeQuery().orderBy("endDate").limit(perStateLimit).get(),
        ]);
        const items = [
          ...scheduled.docs.map((document) => ({
            id: `scheduled:${document.id}`,
            state: "scheduled",
            document,
          })),
          ...active.docs.map((document) => ({
            id: `active:${document.id}`,
            state: "active",
            document,
          })),
        ];
        items.pageFull =
          scheduled.size === perStateLimit || active.size === perStateLimit;
        return items;
      },
      processPage: async (items) => {
        try {
          const result = await commitLifecycleUpdates({
            firestore: db,
            scheduledDocuments: items
              .filter((item) => item.state === "scheduled")
              .map((item) => item.document),
            activeDocuments: items
              .filter((item) => item.state === "active")
              .map((item) => item.document),
            now,
            maxBatchWrites: 450,
          });
          return {
            processed: result.activatedCount + result.completedCount,
            errors: 0,
          };
        } catch (error) {
          logger.error("Lifecycle page failed", {
            itemCount: items.length,
            error: error?.message ?? String(error),
          });
          return { processed: 0, errors: items.length };
        }
      },
      inspectBacklog: async () => {
        const [scheduledCount, activeCount, oldestScheduled, oldestActive] =
          await Promise.all([
            scheduledQuery().count().get(),
            activeQuery().count().get(),
            scheduledQuery().orderBy("startDate").limit(1).get(),
            activeQuery().orderBy("endDate").limit(1).get(),
          ]);
        const eligibleTimes = [
          oldestScheduled.docs[0]?.data().startDate?.toMillis?.(),
          oldestActive.docs[0]?.data().endDate?.toMillis?.(),
        ].filter(Number.isFinite);
        return {
          backlogCount:
            scheduledCount.data().count + activeCount.data().count,
          oldestEligibleAtMillis: eligibleTimes.length > 0
            ? Math.min(...eligibleTimes)
            : null,
        };
      },
      timeBudgetMs: 7 * 60 * 1000,
      pageSize: 450,
    });
    logger.info("Group lifecycle advancement", {
      ...metrics,
      cursorStrategy: "mutation_derived",
    });
  },
);

exports.trackManagedMedia = onObjectFinalized(
  {
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const object = event.data;
    const record = buildMessageAssetRecord(object)
      ?? buildGroupCoverAssetRecord(object)
      ?? buildProfilePhotoAssetRecord(object);
    if (!record) return;
    await registerManagedAsset({
      firestore: db,
      record,
      now: Timestamp.now(),
    });
  },
);

exports.reconcileMessageManagedMedia = onDocumentWritten(
  {
    document: "groups/{groupId}/messages/{messageId}",
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const { groupId, messageId } = event.params;
    const beforeReferences = collectMessageAssetReferences(
      event.data?.before.data(),
      { groupId, messageId },
    );
    const afterReferences = collectMessageAssetReferences(
      event.data?.after.data(),
      { groupId, messageId },
    );
    if (beforeReferences.size === 0 && afterReferences.size === 0) return;
    await reconcileManagedReferences({
      firestore: db,
      storage: admin.storage(),
      beforeReferences,
      afterReferences,
      expectedEntityType: "message",
      expectedEntityId: messageId,
      expectedGroupId: groupId,
      now: Timestamp.now(),
    });
  },
);

exports.reconcileGroupCoverManagedMedia = onDocumentWritten(
  {
    document: "groups/{groupId}",
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const { groupId } = event.params;
    const beforeReferences = collectGroupCoverReference(
      event.data?.before.data(),
      { groupId },
    );
    const afterReferences = collectGroupCoverReference(
      event.data?.after.data(),
      { groupId },
    );
    if (
      beforeReferences.size === afterReferences.size &&
      [...beforeReferences.keys()].every((id) => afterReferences.has(id))
    ) {
      return;
    }
    await reconcileManagedReferences({
      firestore: db,
      storage: admin.storage(),
      beforeReferences,
      afterReferences,
      expectedEntityType: "group_cover",
      expectedEntityId: groupId,
      expectedGroupId: groupId,
      now: Timestamp.now(),
    });
  },
);

exports.reconcileProfilePhotoManagedMedia = onDocumentWritten(
  {
    document: "users_public/{ownerUid}",
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const { ownerUid } = event.params;
    const beforeReferences = collectProfilePhotoReference(
      event.data?.before.data(),
      { ownerUid },
    );
    const afterReferences = collectProfilePhotoReference(
      event.data?.after.data(),
      { ownerUid },
    );
    if (
      beforeReferences.size === afterReferences.size &&
      [...beforeReferences.keys()].every((id) => afterReferences.has(id))
    ) {
      return;
    }
    await reconcileManagedReferences({
      firestore: db,
      storage: admin.storage(),
      beforeReferences,
      afterReferences,
      expectedEntityType: "profile_photo",
      expectedEntityId: ownerUid,
      expectedGroupId: null,
      now: Timestamp.now(),
    });
  },
);

exports.cleanupExpiredData = onSchedule(
  {
    schedule: "every day 03:15",
    region: "us-central1",
    timeZone: "Etc/UTC",
    retryCount: 3,
  },
  async () => {
    const now = Timestamp.now();
    const oldMessageEventCutoff = Timestamp.fromMillis(
      now.toMillis() - 7 * 24 * 60 * 60 * 1000,
    );
    const oldRateLimitCutoff = Timestamp.fromMillis(
      now.toMillis() - 2 * 24 * 60 * 60 * 1000,
    );
    const orphanMediaCutoff = Timestamp.fromMillis(
      now.toMillis() - 24 * 60 * 60 * 1000,
    );
    const drainDeleteQuery = async ({ name, query, timeField }) => {
      const metrics = await drainPagedJob({
        // Deletes remove processed documents from the eligible query. Reading
        // from the head each page is a mutation-derived cursor that also
        // includes inserts arriving around a previous page boundary.
        loadPage: async ({ limit }) => {
          const snapshot = await query()
            .orderBy(timeField)
            .limit(limit)
            .get();
          return snapshot.docs.map((document) => ({
            id: document.id,
            document,
          }));
        },
        processPage: async (items) => {
          try {
            const batch = db.batch();
            for (const item of items) batch.delete(item.document.ref);
            await batch.commit();
            return { processed: items.length, errors: 0 };
          } catch (error) {
            logger.error("Cleanup page failed", {
              name,
              itemCount: items.length,
              error: error?.message ?? String(error),
            });
            return { processed: 0, errors: items.length };
          }
        },
        inspectBacklog: async () => {
          const [count, oldest] = await Promise.all([
            query().count().get(),
            query().orderBy(timeField).limit(1).get(),
          ]);
          return {
            backlogCount: count.data().count,
            oldestEligibleAtMillis:
              oldest.docs[0]?.data()[timeField]?.toMillis?.() ?? null,
          };
        },
        timeBudgetMs: 35 * 1000,
        pageSize: 400,
      });
      return { name, ...metrics, cursorStrategy: "mutation_derived" };
    };

    const cleanupMetrics = [];
    cleanupMetrics.push(await drainDeleteQuery({
      name: "expired_invites",
      query: () => db.collection("invites").where("expiresAt", "<=", now),
      timeField: "expiresAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "expired_feed",
      query: () => db.collectionGroup("insight_feed")
        .where("expiresAt", "<=", now),
      timeField: "expiresAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "message_events",
      query: () => db.collectionGroup("message_events")
        .where("summaryProcessedAt", "<=", oldMessageEventCutoff),
      timeField: "summaryProcessedAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "rate_limits",
      query: () => db.collectionGroup("actions")
        .where("windowStartedAt", "<=", oldRateLimitCutoff),
      timeField: "windowStartedAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "moderation_reports",
      query: () => db.collection("reports")
        .where("retentionExpiresAt", "<=", now),
      timeField: "retentionExpiresAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "moderation_appeals",
      query: () => db.collection("moderation_appeals")
        .where("retentionExpiresAt", "<=", now),
      timeField: "retentionExpiresAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "moderation_audit",
      query: () => db.collection("moderation_audit")
        .where("retentionExpiresAt", "<=", now),
      timeField: "retentionExpiresAt",
    }));
    cleanupMetrics.push(await drainDeleteQuery({
      name: "moderation_appeal_audit",
      query: () => db.collection("moderation_appeal_audit")
        .where("retentionExpiresAt", "<=", now),
      timeField: "retentionExpiresAt",
    }));

    const drainManagedMedia = async ({
      name,
      query,
      timeField,
    }) => {
      let committedCount = 0;
      let deletedCount = 0;
      const metrics = await drainPagedJob({
        loadPage: async ({ limit }) => {
          const snapshot = await query().orderBy(timeField).limit(limit).get();
          return snapshot.docs.map((document) => ({
            id: document.id,
            document,
          }));
        },
        processPage: async (items) => {
          let errors = 0;
          let processed = 0;
          for (const item of items) {
            try {
              const result = await reconcileExpiredManagedAsset({
                firestore: db,
                storage: admin.storage(),
                assetDocument: item.document,
                now,
              });
              if (result === "committed") committedCount += 1;
              if (result === "deleted") deletedCount += 1;
              processed += 1;
            } catch (error) {
              errors += 1;
              logger.error("Managed media cleanup item failed", {
                name,
                assetId: item.id,
                error: error?.message ?? String(error),
              });
            }
          }
          return { processed, errors };
        },
        inspectBacklog: async () => {
          const [count, oldest] = await Promise.all([
            query().count().get(),
            query().orderBy(timeField).limit(1).get(),
          ]);
          return {
            backlogCount: count.data().count,
            oldestEligibleAtMillis:
              oldest.docs[0]?.data()[timeField]?.toMillis?.() ?? null,
          };
        },
        timeBudgetMs: 35 * 1000,
        pageSize: 200,
      });
      return {
        name,
        ...metrics,
        committedCount,
        deletedCount,
        cursorStrategy: "mutation_derived",
      };
    };
    cleanupMetrics.push(await drainManagedMedia({
      name: "pending_media",
      query: () => db.collection("managed_assets")
        .where("status", "==", "pending")
        .where("createdAt", "<=", orphanMediaCutoff),
      timeField: "createdAt",
    }));
    cleanupMetrics.push(await drainManagedMedia({
      name: "pending_media_deletion",
      query: () => db.collection("managed_assets")
        .where("status", "==", "delete_pending"),
      timeField: "deletePendingAt",
    }));

    logger.info("Expired data cleanup", { jobs: cleanupMetrics });
  },
);

exports.sendPushNotification = onDocumentCreated(
  {
    document: "groups/{groupId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const messageData = event.data?.data();
    if (!messageData?.senderId) return;

    const { groupId, messageId } = event.params;
    const senderId = messageData.senderId;
    const [groupSnapshot, senderSnapshot] = await Promise.all([
      db.doc(`groups/${groupId}`).get(),
      db.doc(`users_public/${senderId}`).get(),
    ]);
    if (!groupSnapshot.exists) return;

    const group = groupSnapshot.data();
    const groupName = typeof group.name === "string"
      ? group.name.slice(0, 80)
      : "Study Group";
    const senderNameValue = senderSnapshot.exists
      ? senderSnapshot.data().displayName
      : "A group member";
    const senderName = typeof senderNameValue === "string"
      ? senderNameValue.slice(0, 80)
      : "A group member";
    const recipientIds = (group.members ?? []).filter(
      (memberId) => memberId !== senderId,
    );

    const eventRef = db.doc(
      `groups/${groupId}/message_events/${messageId}`,
    );
    await db.runTransaction(async (transaction) => {
      const eventSnapshot = await transaction.get(eventRef);
      if (eventSnapshot.exists) return;

      const unreadUpdates = {};
      for (const recipientId of recipientIds) {
        unreadUpdates[`unreadCounts.${recipientId}`] = FieldValue.increment(1);
      }
      transaction.update(db.doc(`groups/${groupId}`), {
        ...groupSummaryFromMessage({
          messageId,
          message: messageData,
          canonicalSenderName: senderName,
          fallbackTimestamp: Timestamp.now(),
        }),
        ...unreadUpdates,
      });
      transaction.create(eventRef, {
        schemaVersion: 1,
        messageId,
        summaryProcessedAt: Timestamp.now(),
      });
    });

    if (recipientIds.length === 0) return;

    const stateSnapshots = await db.getAll(
      ...recipientIds.map(
        (uid) => db.doc(`users/${uid}/group_state/${groupId}`),
      ),
    );
    const nowMillis = Date.now();
    const enabledRecipients = recipientIds.filter((uid, index) => {
      const state = stateSnapshots[index].exists
        ? stateSnapshots[index].data()
        : {};
      return !state.mutedUntil
        || state.mutedUntil.toMillis() <= nowMillis;
    });

    const deviceQueries = await Promise.all(
      enabledRecipients.map((uid) => db
        .collection(`users/${uid}/devices`)
        .where("notificationsEnabled", "==", true)
        .limit(10)
        .get()),
    );
    const devices = [];
    for (const querySnapshot of deviceQueries) {
      for (const deviceSnapshot of querySnapshot.docs) {
        const device = deviceSnapshot.data();
        if (typeof device.token === "string" && device.token) {
          if (device.messageNotifications !== false) {
            devices.push({
              token: device.token,
              reference: deviceSnapshot.ref,
              previewContent: device.previewContent === true,
            });
          }
        }
      }
    }

    const uniqueDevices = [
      ...new Map(devices.map((device) => [device.token, device])).values(),
    ];
    if (uniqueDevices.length === 0) return;

    const cleanup = [];
    let successCount = 0;
    let failureCount = 0;
    const sendToDevices = async (targetDevices, body) => {
      if (targetDevices.length === 0) return;
      const response = await admin.messaging().sendEachForMulticast({
        notification: {
          title: `${senderName} in ${groupName}`,
          body,
        },
        data: messageNotificationData({
          groupId,
          messageId,
          space: ["reflection", "discussion", "prayer"].includes(
            messageData.space,
          )
            ? messageData.space
            : "discussion",
        }),
        android: {
          collapseKey: `group-${groupId}`,
          notification: {
            channelId: "braid_messages",
            tag: `group-${groupId}`,
          },
        },
        apns: {
          payload: {
            aps: {
              threadId: `group-${groupId}`,
            },
          },
        },
        tokens: targetDevices.map((device) => device.token),
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
      response.responses.forEach((result, index) => {
        if (!result.success
          && isInvalidMessagingTokenError(result.error?.code)) {
          cleanup.push(targetDevices[index].reference.delete());
        }
      });
    };
    await Promise.all([
      sendToDevices(
        uniqueDevices.filter((device) => device.previewContent),
        messagePreview(messageData.parts),
      ),
      sendToDevices(
        uniqueDevices.filter((device) => !device.previewContent),
        "Open Braid to view this update.",
      ),
    ]);
    await Promise.allSettled(cleanup);

    logger.info("Group notification result", {
      groupId,
      messageId,
      recipientCount: uniqueDevices.length,
      successCount,
      failureCount,
      removedInvalidTokenCount: cleanup.length,
    });
  },
);

exports.reconcileGroupMessageSummary = onDocumentWritten(
  {
    document: "groups/{groupId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    if (!event.data?.before.exists || event.data.after.exists &&
        event.data.before.data()?.isDeleted ===
          event.data.after.data()?.isDeleted &&
        JSON.stringify(event.data.before.data()?.parts ?? []) ===
          JSON.stringify(event.data.after.data()?.parts ?? [])) {
      return;
    }

    const { groupId, messageId } = event.params;
    const groupRef = db.doc(`groups/${groupId}`);
    const latestQuery = db
      .collection(`groups/${groupId}/messages`)
      .where("isDeleted", "==", false)
      .orderBy("timestamp", "desc")
      .limit(1);
    await db.runTransaction(async (transaction) => {
      const groupSnapshot = await transaction.get(groupRef);
      if (!groupSnapshot.exists) return;
      const latestSnapshot = await transaction.get(latestQuery);
      const latest = latestSnapshot.docs[0];
      if (!shouldReconcileGroupSummary({
        lastMessageId: groupSnapshot.data().lastMessageId,
        changedMessageId: messageId,
        latestMessageId: latest?.id,
      })) return;

      if (latestSnapshot.empty) {
        transaction.update(groupRef, {
          lastMessageId: FieldValue.delete(),
          lastMessageTime: FieldValue.delete(),
          lastMessageText: FieldValue.delete(),
          lastMessageSenderName: FieldValue.delete(),
          lastMessageSenderId: FieldValue.delete(),
        });
        return;
      }

      const latestData = latest.data();
      const senderSnapshot = await transaction.get(
        db.doc(`users_public/${latestData.senderId}`),
      );
      const canonicalName = senderSnapshot.exists &&
          typeof senderSnapshot.data().displayName === "string"
        ? senderSnapshot.data().displayName.slice(0, 80)
        : "A group member";
      transaction.update(groupRef, groupSummaryFromMessage({
        messageId: latest.id,
        message: latestData,
        canonicalSenderName: canonicalName,
        fallbackTimestamp: Timestamp.now(),
      }));
    });
  },
);
