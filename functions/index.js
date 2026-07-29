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
  parseMessageAssetPath,
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

admin.initializeApp();

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;
const enforceAppCheck = defineBoolean("ENFORCE_APP_CHECK", {
  default: false,
  description: "Reject callable requests without a valid App Check token.",
});

const callableOptions = {
  region: "us-central1",
  enforceAppCheck,
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
  { minIntervalMs, dailyLimit },
) {
  const rateRef = db.doc(`rate_limits/${uid}/actions/${action}`);
  const rateSnapshot = await transaction.get(rateRef);
  const current = rateSnapshot.exists ? rateSnapshot.data() : {};
  const windowStartedAt = current.windowStartedAt?.toMillis?.() ?? 0;
  const nowMillis = now.toMillis();
  const withinWindow = nowMillis - windowStartedAt < 24 * 60 * 60 * 1000;
  const count = withinWindow ? current.count ?? 0 : 0;
  const lastCreatedAt = current.lastCreatedAt?.toMillis?.() ?? 0;

  if (nowMillis - lastCreatedAt < minIntervalMs) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait before trying that again.",
    );
  }
  if (count >= dailyLimit) {
    throw new HttpsError(
      "resource-exhausted",
      "Daily limit reached. Please try again tomorrow.",
    );
  }

  transaction.set(
    rateRef,
    {
      windowStartedAt: withinWindow ? current.windowStartedAt : now,
      count: count + 1,
      lastCreatedAt: now,
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
    { minIntervalMs: 10 * 1000, dailyLimit: 30 },
  );
}

exports.createStudyGroup = onCall(callableOptions, async (request) => {
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
    const batch = db.batch();

    batch.create(groupRef, {
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
    batch.create(memberRef, {
      schemaVersion: 2,
      uid,
      role: "owner",
      status: "active",
      joinedAt: now,
      invitedBy: uid,
    });
    await batch.commit();

    return { groupId: groupRef.id };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.createGroupInvite = onCall(callableOptions, async (request) => {
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
      const group = await requireGroupOwner(transaction, groupRef, uid);
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

exports.redeemGroupInvite = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);

  try {
    const token = requireString(request.data?.token, "token", 512, {
      minLength: 32,
    });
    const inviteId = hashInviteToken(token);
    const inviteRef = db.doc(`invites/${inviteId}`);
    const now = Timestamp.now();

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
      const inviteePrivateRef = db.doc(`users_private/${uid}`);
      const inviterPrivateRef = db.doc(`users_private/${inviterUid}`);
      const [
        inviteeConnectionSnapshot,
        inviterConnectionSnapshot,
        inviteeBlockSnapshot,
        inviterBlockSnapshot,
        inviteePrivateSnapshot,
        inviterPrivateSnapshot,
      ] = await Promise.all([
        transaction.get(inviteeConnectionRef),
        transaction.get(inviterConnectionRef),
        transaction.get(inviteeBlockRef),
        transaction.get(inviterBlockRef),
        transaction.get(inviteePrivateRef),
        transaction.get(inviterPrivateRef),
      ]);
      if (inviteeBlockSnapshot.exists || inviterBlockSnapshot.exists) {
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
    publishedAt: insight.createdAt ?? Timestamp.now(),
    updatedAt: insight.updatedAt ?? Timestamp.now(),
    expiresAt: insight.expiresAt,
    sourceId,
  };
}

exports.publishInsight = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const { title, body, themeId } = normalizeInsightInput(request.data);

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + 3 * 24 * 60 * 60 * 1000,
    );
    const insightRef = db.collection("insights").doc();
    const profileRef = db.doc(`users_public/${uid}`);

    await db.runTransaction(async (transaction) => {
      const profileSnapshot = await transaction.get(profileRef);
      if (!profileSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Complete your profile before sharing an Insight.",
        );
      }
      await enforceDailyRateLimit(
        transaction,
        uid,
        "publish_insight",
        now,
        { minIntervalMs: 30 * 1000, dailyLimit: 20 },
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
    return { insightId: insightRef.id, expiresAtMillis: expiresAt.toMillis() };
  } catch (error) {
    throw invalidArgument(error);
  }
});

exports.submitReport = onCall(callableOptions, async (request) => {
  const uid = authenticatedUid(request);
  try {
    const {
      targetType,
      targetId,
      groupId,
      reason,
      details,
    } = normalizeReportInput(request.data);
    const now = Timestamp.now();
    const reportRef = db.collection("reports").doc();
    await db.runTransaction(async (transaction) => {
      await enforceDailyRateLimit(
        transaction,
        uid,
        "submit_report",
        now,
        { minIntervalMs: 5 * 1000, dailyLimit: 20 },
      );
      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterUid: uid,
        targetType,
        targetId,
        ...(groupId ? { groupId } : {}),
        reason,
        ...(details ? { details } : {}),
        status: "open",
        createdAt: now,
      });
    });
    return { reportId: reportRef.id };
  } catch (error) {
    throw invalidArgument(error);
  }
});

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
  {
    ...callableOptions,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
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

    const groupsSnapshot = await db
      .collection("groups")
      .where("members", "array-contains", uid)
      .get();
    const ownedSharedGroups = groupsSnapshot.docs.filter((document) => {
      const group = document.data();
      return group.ownerId === uid && (group.members ?? []).length > 1;
    });
    if (ownedSharedGroups.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        "Transfer ownership of every shared study before deleting your account.",
      );
    }

    for (const groupDocument of groupsSnapshot.docs) {
      const group = groupDocument.data();
      if (group.ownerId === uid) {
        await db.recursiveDelete(groupDocument.ref);
      } else {
        await groupDocument.ref.update({
          members: FieldValue.arrayRemove(uid),
          [`readingProgress.${uid}`]: FieldValue.delete(),
          [`userCompletedChapters.${uid}`]: FieldValue.delete(),
          [`unreadCounts.${uid}`]: FieldValue.delete(),
        });
        await groupDocument.ref.collection("members").doc(uid).set({
          status: "deleted_account",
          removedAt: Timestamp.now(),
        }, { merge: true });
      }
    }

    const [
      insightsSnapshot,
      messagesSnapshot,
      commentsSnapshot,
      reactionsSnapshot,
      blockedBySnapshot,
      connectionsSnapshot,
      createdInvitesSnapshot,
    ] =
      await Promise.all([
        db.collection("insights").where("authorUid", "==", uid).get(),
        db.collectionGroup("messages").where("senderId", "==", uid).get(),
        db.collectionGroup("comments").where("authorUid", "==", uid).get(),
        db.collectionGroup("reactions").where("uid", "==", uid).get(),
        db.collectionGroup("blocks").where("blockedUid", "==", uid).get(),
        db.collection(`users/${uid}/connections`).get(),
        db.collection("invites").where("createdBy", "==", uid).get(),
      ]);
    for (const insight of insightsSnapshot.docs) {
      await db.recursiveDelete(insight.ref);
    }

    const bulkWriter = db.bulkWriter();
    const reciprocalPrivateSnapshots = connectionsSnapshot.empty
      ? []
      : await db.getAll(
        ...connectionsSnapshot.docs.map(
          (connection) => db.doc(`users_private/${connection.id}`),
        ),
      );
    for (const message of messagesSnapshot.docs) {
      bulkWriter.update(message.ref, {
        senderName: "Deleted account",
        senderPhotoUrl: FieldValue.delete(),
        parts: [],
        isDeleted: true,
        deletedAt: Timestamp.now(),
      });
    }
    for (const comment of commentsSnapshot.docs) {
      bulkWriter.delete(comment.ref);
    }
    for (const reaction of reactionsSnapshot.docs) {
      bulkWriter.delete(reaction.ref);
    }
    for (const block of blockedBySnapshot.docs) {
      bulkWriter.delete(block.ref);
    }
    for (let index = 0; index < connectionsSnapshot.docs.length; index++) {
      const connection = connectionsSnapshot.docs[index];
      bulkWriter.delete(
        db.doc(`users/${connection.id}/connections/${uid}`),
      );
      const reciprocalPrivate = reciprocalPrivateSnapshots[index];
      if (reciprocalPrivate?.exists
        && (reciprocalPrivate.data().connectionCount ?? 0) > 0) {
        bulkWriter.update(reciprocalPrivate.ref, {
          connectionCount: FieldValue.increment(-1),
          updatedAt: Timestamp.now(),
        });
      }
    }
    for (const invite of createdInvitesSnapshot.docs) {
      bulkWriter.delete(invite.ref);
    }
    await bulkWriter.close();

    await mapInChunks(
      messagesSnapshot.docs,
      20,
      (message) => {
        const groupId = message.ref.parent.parent?.id;
        if (!groupId) return Promise.resolve();
        return admin.storage().bucket().deleteFiles({
          prefix: `groups/${groupId}/messages/${message.id}/`,
          force: true,
        });
      },
    );

    await Promise.all([
      db.recursiveDelete(db.doc(`users/${uid}`)),
      db.recursiveDelete(db.doc(`rate_limits/${uid}`)),
      db.doc(`users_public/${uid}`).delete(),
      db.doc(`users_private/${uid}`).delete(),
      admin.storage().bucket().deleteFiles({
        prefix: `users/${uid}/`,
        force: true,
      }),
    ]);
    await admin.auth().deleteUser(uid);

    logger.info("Account deletion completed", { uid });
    return { deleted: true };
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
    const [scheduledSnapshot, activeSnapshot] = await Promise.all([
      db.collection("groups")
        .where("lifecycle", "==", "scheduled")
        .where("startDate", "<=", now)
        .limit(400)
        .get(),
      db.collection("groups")
        .where("lifecycle", "==", "active")
        .where("endDate", "<=", now)
        .limit(400)
        .get(),
    ]);
    if (scheduledSnapshot.empty && activeSnapshot.empty) return;
    const result = await commitLifecycleUpdates({
      firestore: db,
      scheduledDocuments: scheduledSnapshot.docs,
      activeDocuments: activeSnapshot.docs,
      now,
    });
    logger.info("Group lifecycle advancement", {
      activatedCount: result.activatedCount,
      completedCount: result.completedCount,
      batchCount: result.batchCount,
    });
  },
);

exports.trackPendingMessageMedia = onObjectFinalized(
  {
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const object = event.data;
    const identity = parseMessageAssetPath(object.name);
    if (!identity || !object.bucket) return;

    const messageRef = db.doc(
      `groups/${identity.groupId}/messages/${identity.messageId}`,
    );
    if ((await messageRef.get()).exists) return;

    const manifestId = Buffer.from(object.name, "utf8").toString("base64url");
    await db.doc(`pending_message_media/${manifestId}`).set({
      schemaVersion: 1,
      objectName: object.name,
      bucket: object.bucket,
      groupId: identity.groupId,
      messageId: identity.messageId,
      ownerId: typeof object.metadata?.ownerId === "string"
        ? object.metadata.ownerId
        : null,
      uploadedAt: Timestamp.fromDate(
        object.timeCreated ? new Date(object.timeCreated) : new Date(),
      ),
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
    const [
      inviteSnapshot,
      feedSnapshot,
      eventSnapshot,
      rateSnapshot,
      mediaSnapshot,
    ] = await Promise.all([
      db.collection("invites")
        .where("expiresAt", "<=", now)
        .limit(400)
        .get(),
      db.collectionGroup("insight_feed")
        .where("expiresAt", "<=", now)
        .limit(400)
        .get(),
      db.collectionGroup("message_events")
        .where("summaryProcessedAt", "<=", oldMessageEventCutoff)
        .limit(400)
        .get(),
      db.collectionGroup("actions")
        .where("windowStartedAt", "<=", oldRateLimitCutoff)
        .limit(400)
        .get(),
      db.collection("pending_message_media")
        .where("uploadedAt", "<=", orphanMediaCutoff)
        .limit(250)
        .get(),
    ]);

    const bulkWriter = db.bulkWriter();
    for (const snapshot of [
      inviteSnapshot,
      feedSnapshot,
      eventSnapshot,
      rateSnapshot,
    ]) {
      for (const document of snapshot.docs) {
        bulkWriter.delete(document.ref);
      }
    }

    let removedOrphanMediaCount = 0;
    for (const document of mediaSnapshot.docs) {
      const media = document.data();
      const identity = parseMessageAssetPath(media.objectName);
      if (!identity || typeof media.bucket !== "string") {
        bulkWriter.delete(document.ref);
        continue;
      }
      const messageExists = (await db.doc(
        `groups/${identity.groupId}/messages/${identity.messageId}`,
      ).get()).exists;
      if (!messageExists) {
        await admin.storage().bucket(media.bucket).file(media.objectName)
          .delete({ ignoreNotFound: true });
        removedOrphanMediaCount += 1;
      }
      bulkWriter.delete(document.ref);
    }
    await bulkWriter.close();

    logger.info("Expired data cleanup", {
      expiredInviteCount: inviteSnapshot.size,
      expiredFeedPointerCount: feedSnapshot.size,
      oldMessageEventCount: eventSnapshot.size,
      oldRateLimitCount: rateSnapshot.size,
      reviewedPendingMediaCount: mediaSnapshot.size,
      removedOrphanMediaCount,
    });
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
