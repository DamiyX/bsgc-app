const { parseMessageAssetPath } = require("./contracts");

const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const AUDIO_TYPES = new Set([
  "audio/aac",
  "audio/m4a",
  "audio/mp4",
  "audio/mpeg",
  "audio/ogg",
  "audio/wav",
  "audio/webm",
]);

function managedAssetIdForPath(storagePath) {
  if (typeof storagePath !== "string" || storagePath.length === 0) return null;
  return Buffer.from(storagePath, "utf8").toString("base64url");
}

function parseGroupCoverPath(storagePath) {
  if (typeof storagePath !== "string") return null;
  const match = storagePath.match(
    /^groups\/([A-Za-z0-9_-]{1,160})\/covers\/([A-Za-z0-9_.-]{1,160})$/,
  );
  return match ? { groupId: match[1], fileName: match[2] } : null;
}

function parseProfilePhotoPath(storagePath) {
  if (typeof storagePath !== "string") return null;
  const match = storagePath.match(
    /^users\/([A-Za-z0-9_-]{1,160})\/profile\/([A-Za-z0-9_.-]{1,160})$/,
  );
  return match ? { ownerUid: match[1], fileName: match[2] } : null;
}

function isCanonicalMessageAssetPath(storagePath) {
  return parseMessageAssetPath(storagePath) !== null;
}

async function deleteUnregisteredMessageAsset({ storage, object }) {
  if (
    !isCanonicalMessageAssetPath(object?.name)
    || typeof object?.bucket !== "string"
  ) {
    return false;
  }
  await storage.bucket(object.bucket).file(object.name).delete({
    ignoreNotFound: true,
  });
  return true;
}

function buildProfilePhotoAssetRecord(object) {
  const identity = parseProfilePhotoPath(object?.name);
  const metadata = object?.metadata;
  const sizeBytes = Number(object?.size);
  const mimeType = object?.contentType;
  const expectedAssetId = managedAssetIdForPath(object?.name);
  if (
    !identity ||
    typeof object?.bucket !== "string" ||
    !metadata ||
    metadata.assetId !== expectedAssetId ||
    metadata.ownerId !== identity.ownerUid ||
    !IMAGE_TYPES.has(mimeType) ||
    !Number.isSafeInteger(sizeBytes) ||
    sizeBytes < 1 ||
    sizeBytes > 5 * 1024 * 1024
  ) {
    return null;
  }
  const createdAt = object.timeCreated
    ? new Date(object.timeCreated)
    : new Date();
  if (Number.isNaN(createdAt.getTime())) return null;
  return {
    schemaVersion: 1,
    assetId: expectedAssetId,
    bucket: object.bucket,
    storagePath: object.name,
    ownerUid: identity.ownerUid,
    entityType: "profile_photo",
    entityId: identity.ownerUid,
    groupId: null,
    mimeType,
    sizeBytes,
    ...(typeof object.crc32c === "string" && object.crc32c.length > 0
      ? { checksum: object.crc32c }
      : {}),
    status: "pending",
    createdAt,
  };
}

function buildGroupCoverAssetRecord(object) {
  const identity = parseGroupCoverPath(object?.name);
  const metadata = object?.metadata;
  const sizeBytes = Number(object?.size);
  const mimeType = object?.contentType;
  const expectedAssetId = managedAssetIdForPath(object?.name);
  if (
    !identity ||
    typeof object?.bucket !== "string" ||
    !metadata ||
    metadata.assetId !== expectedAssetId ||
    metadata.groupId !== identity.groupId ||
    typeof metadata.ownerId !== "string" ||
    !IMAGE_TYPES.has(mimeType) ||
    !Number.isSafeInteger(sizeBytes) ||
    sizeBytes < 1 ||
    sizeBytes > 5 * 1024 * 1024
  ) {
    return null;
  }
  const createdAt = object.timeCreated
    ? new Date(object.timeCreated)
    : new Date();
  if (Number.isNaN(createdAt.getTime())) return null;
  return {
    schemaVersion: 1,
    assetId: expectedAssetId,
    bucket: object.bucket,
    storagePath: object.name,
    ownerUid: metadata.ownerId,
    entityType: "group_cover",
    entityId: identity.groupId,
    groupId: identity.groupId,
    mimeType,
    sizeBytes,
    ...(typeof object.crc32c === "string" && object.crc32c.length > 0
      ? { checksum: object.crc32c }
      : {}),
    status: "pending",
    createdAt,
  };
}

function buildMessageAssetRecord(object) {
  const identity = parseMessageAssetPath(object?.name);
  if (!identity || typeof object?.bucket !== "string") return null;

  const metadata = object.metadata;
  if (!metadata || typeof metadata !== "object") return null;
  const expectedAssetId = managedAssetIdForPath(object.name);
  if (
    metadata.assetId !== expectedAssetId ||
    metadata.groupId !== identity.groupId ||
    metadata.messageId !== identity.messageId ||
    typeof metadata.ownerId !== "string" ||
    !/^[A-Za-z0-9_-]{1,160}$/.test(metadata.ownerId)
  ) {
    return null;
  }

  const sizeBytes = Number(object.size);
  const mimeType = object.contentType;
  const isImage = IMAGE_TYPES.has(mimeType);
  const isAudio = AUDIO_TYPES.has(mimeType);
  if (
    !Number.isSafeInteger(sizeBytes) ||
    sizeBytes < 1 ||
    (!isImage && !isAudio) ||
    (isImage && sizeBytes > 10 * 1024 * 1024) ||
    (isAudio && sizeBytes > 25 * 1024 * 1024)
  ) {
    return null;
  }

  const createdAt = object.timeCreated
    ? new Date(object.timeCreated)
    : new Date();
  if (Number.isNaN(createdAt.getTime())) return null;

  return {
    schemaVersion: 1,
    assetId: expectedAssetId,
    bucket: object.bucket,
    storagePath: object.name,
    ownerUid: metadata.ownerId,
    entityType: "message",
    entityId: identity.messageId,
    groupId: identity.groupId,
    mimeType,
    sizeBytes,
    ...(typeof object.crc32c === "string" && object.crc32c.length > 0
      ? { checksum: object.crc32c }
      : {}),
    status: "pending",
    createdAt,
  };
}

function collectGroupCoverReference(group, { groupId } = {}) {
  const references = new Map();
  if (
    !group ||
    typeof group.ownerId !== "string" ||
    typeof group.photoUrl !== "string"
  ) {
    return references;
  }
  const identity = parseGroupCoverPath(group.photoUrl);
  if (!identity || identity.groupId !== groupId) return references;
  const assetId = managedAssetIdForPath(group.photoUrl);
  references.set(assetId, {
    assetId,
    storagePath: group.photoUrl,
    ownerUid: group.ownerId,
  });
  return references;
}

function collectProfilePhotoReference(profile, { ownerUid } = {}) {
  const references = new Map();
  if (!profile || typeof profile.photoUrl !== "string") return references;
  const identity = parseProfilePhotoPath(profile.photoUrl);
  if (!identity || identity.ownerUid !== ownerUid) return references;
  const assetId = managedAssetIdForPath(profile.photoUrl);
  references.set(assetId, {
    assetId,
    storagePath: profile.photoUrl,
    ownerUid,
  });
  return references;
}

function collectMessageAssetReferences(message, { groupId, messageId } = {}) {
  const references = new Map();
  if (!message || typeof message !== "object") return references;
  if (
    typeof message.senderId !== "string" ||
    typeof groupId !== "string" ||
    typeof messageId !== "string" ||
    !Array.isArray(message.parts)
  ) {
    return references;
  }

  for (const part of message.parts) {
    if (!part || !["image", "voice"].includes(part.type)) continue;
    const identity = parseMessageAssetPath(part.content);
    if (
      typeof part.assetId !== "string" ||
      !identity ||
      identity.groupId !== groupId ||
      identity.messageId !== messageId ||
      part.assetId !== managedAssetIdForPath(part.content)
    ) {
      continue;
    }
    references.set(part.assetId, {
      assetId: part.assetId,
      storagePath: part.content,
      ownerUid: message.senderId,
      mediaType: part.type,
    });
  }
  return references;
}

function nextManagedAssetStatus(currentStatus, action) {
  if (currentStatus === "deleted") return "deleted";
  if (action === "commit") {
    return currentStatus === "pending" ? "committed" : currentStatus;
  }
  if (action === "queueDeletion") {
    return currentStatus === "pending" || currentStatus === "committed"
      ? "delete_pending"
      : currentStatus;
  }
  if (action === "deleted") {
    return currentStatus === "delete_pending" ? "deleted" : currentStatus;
  }
  return currentStatus;
}

async function registerManagedAsset({
  firestore,
  record,
  now,
}) {
  const assetRef = firestore.doc(`managed_assets/${record.assetId}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(assetRef);
    if (snapshot.exists) {
      const existing = snapshot.data();
      if (
        existing.storagePath !== record.storagePath ||
        existing.bucket !== record.bucket ||
        existing.ownerUid !== record.ownerUid
      ) {
        throw new Error("Managed asset identity collision.");
      }
      if (existing.status !== "pending") return;
    }
    transaction.set(assetRef, {
      ...record,
      createdAt: record.createdAt,
      updatedAt: now,
    }, { merge: true });
  });
}

async function reconcileManagedReferences({
  firestore,
  storage,
  beforeReferences,
  afterReferences,
  expectedEntityType,
  expectedEntityId,
  expectedGroupId,
  now,
}) {
  for (const [assetId, reference] of afterReferences) {
    if (beforeReferences.has(assetId)) continue;
    const assetRef = firestore.doc(`managed_assets/${assetId}`);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(assetRef);
      if (!snapshot.exists) throw new Error("Managed asset is not registered.");
      const asset = snapshot.data();
      if (
        asset.assetId !== assetId ||
        asset.storagePath !== reference.storagePath ||
        asset.ownerUid !== reference.ownerUid ||
        asset.entityType !== expectedEntityType ||
        asset.entityId !== expectedEntityId ||
        asset.groupId !== expectedGroupId ||
        !["pending", "committed"].includes(asset.status)
      ) {
        throw new Error("Managed asset does not match its owning entity.");
      }
      if (asset.status === "pending") {
        transaction.update(assetRef, {
          status: "committed",
          committedAt: now,
          updatedAt: now,
        });
      }
    });
  }

  for (const [assetId, reference] of beforeReferences) {
    if (afterReferences.has(assetId)) continue;
    const assetRef = firestore.doc(`managed_assets/${assetId}`);
    const queued = await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(assetRef);
      if (!snapshot.exists) return null;
      const asset = snapshot.data();
      if (
        asset.storagePath !== reference.storagePath ||
        asset.entityType !== expectedEntityType ||
        asset.entityId !== expectedEntityId ||
        asset.groupId !== expectedGroupId
      ) {
        throw new Error("Refusing to delete a mismatched managed asset.");
      }
      if (asset.status === "deleted") return null;
      if (asset.status !== "delete_pending") {
        transaction.update(assetRef, {
          status: "delete_pending",
          deletePendingAt: now,
          updatedAt: now,
        });
      }
      return { bucket: asset.bucket, storagePath: asset.storagePath };
    });
    if (!queued) continue;
    await storage.bucket(queued.bucket).file(queued.storagePath).delete({
      ignoreNotFound: true,
    });
    await assetRef.update({
      status: "deleted",
      deletedAt: now,
      updatedAt: now,
    });
  }
}

async function reconcileExpiredManagedAsset({
  firestore,
  storage,
  assetDocument,
  now,
}) {
  const asset = assetDocument.data();
  if (!["pending", "delete_pending"].includes(asset.status)) return "ignored";

  if (asset.status === "pending") {
    let isReferenced = false;
    if (asset.entityType === "message") {
      const snapshot = await firestore.doc(
        `groups/${asset.groupId}/messages/${asset.entityId}`,
      ).get();
      isReferenced = collectMessageAssetReferences(
        snapshot.data(),
        { groupId: asset.groupId, messageId: asset.entityId },
      ).has(asset.assetId);
    } else if (asset.entityType === "group_cover") {
      const snapshot = await firestore.doc(`groups/${asset.entityId}`).get();
      isReferenced = collectGroupCoverReference(
        snapshot.data(),
        { groupId: asset.entityId },
      ).has(asset.assetId);
    } else if (asset.entityType === "profile_photo") {
      const snapshot = await firestore.doc(
        `users_public/${asset.entityId}`,
      ).get();
      isReferenced = collectProfilePhotoReference(
        snapshot.data(),
        { ownerUid: asset.entityId },
      ).has(asset.assetId);
    }
    if (isReferenced) {
      await assetDocument.ref.update({
        status: "committed",
        committedAt: now,
        updatedAt: now,
      });
      return "committed";
    }
    await assetDocument.ref.update({
      status: "delete_pending",
      deletePendingAt: now,
      updatedAt: now,
    });
  }

  await storage.bucket(asset.bucket).file(asset.storagePath).delete({
    ignoreNotFound: true,
  });
  await assetDocument.ref.update({
    status: "deleted",
    deletedAt: now,
    updatedAt: now,
  });
  return "deleted";
}

module.exports = {
  buildGroupCoverAssetRecord,
  buildMessageAssetRecord,
  buildProfilePhotoAssetRecord,
  collectGroupCoverReference,
  collectMessageAssetReferences,
  collectProfilePhotoReference,
  deleteUnregisteredMessageAsset,
  isCanonicalMessageAssetPath,
  managedAssetIdForPath,
  nextManagedAssetStatus,
  parseGroupCoverPath,
  parseProfilePhotoPath,
  reconcileManagedReferences,
  reconcileExpiredManagedAsset,
  registerManagedAsset,
};
