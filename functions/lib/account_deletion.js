"use strict";

const ACCOUNT_DELETION_PHASES = Object.freeze([
  "preflight",
  "freeze",
  "memberships",
  "insights",
  "messages",
  "comments",
  "reactions",
  "blocks",
  "relationships",
  "invites",
  "reports",
  "media",
  "ownedData",
  "finalizeIdentity",
  "verify",
]);

async function processDeletionStep({ job, handlers }) {
  const phase = job.phase ?? ACCOUNT_DELETION_PHASES[0];
  const phaseIndex = ACCOUNT_DELETION_PHASES.indexOf(phase);
  if (phaseIndex < 0) {
    throw new Error(`Unknown account deletion phase: ${phase}`);
  }
  const handler = handlers[phase];
  if (typeof handler !== "function") {
    throw new Error(`Missing account deletion handler: ${phase}`);
  }
  const result = await handler();
  const completedPages = Number.isInteger(job.completedPages)
    ? job.completedPages
    : 0;
  if (!result.done) {
    return {
      phase: result.nextPhase ?? phase,
      completedPages: completedPages + (result.processed > 0 ? 1 : 0),
      processedInLastPage: result.processed ?? 0,
      cursor: result.cursor ?? job.cursor ?? null,
      complete: false,
    };
  }
  const nextPhase = ACCOUNT_DELETION_PHASES[phaseIndex + 1];
  return {
    phase: nextPhase ?? "complete",
    completedPages,
    processedInLastPage: result.processed ?? 0,
    cursor: null,
    complete: nextPhase == null,
  };
}

function createAccountDeletionHandlers({
  uid,
  db,
  auth,
  bucket,
  FieldValue,
  Timestamp,
  FieldPath,
  job,
}) {
  const deleteDocuments = async (query, pageSize) => {
    const snapshot = await query.limit(pageSize).get();
    if (!snapshot.empty) {
      const batch = db.batch();
      for (const document of snapshot.docs) batch.delete(document.ref);
      await batch.commit();
    }
    return {
      done: snapshot.size < pageSize,
      processed: snapshot.size,
    };
  };

  const ignoreMissingAuthUser = async (operation) => {
    try {
      await operation();
    } catch (error) {
      if (error?.code !== "auth/user-not-found") throw error;
    }
  };

  const deleteStorageObject = async (asset) => {
    try {
      await bucket.file(asset.storagePath).delete();
    } catch (error) {
      if (error?.code !== 404 && error?.code !== "storage/object-not-found") {
        throw error;
      }
    }
  };

  const deleteManagedAssetDocuments = async (documents) => {
    if (documents.length === 0) return;
    for (const document of documents) {
      await deleteStorageObject(document.data());
    }
    const batch = db.batch();
    for (const document of documents) batch.delete(document.ref);
    await batch.commit();
  };

  return {
    preflight: async () => {
      let query = db.collection("groups")
        .where("ownerId", "==", uid)
        .orderBy(FieldPath.documentId())
        .limit(50);
      if (typeof job.cursor === "string" && job.cursor.length > 0) {
        query = query.startAfter(job.cursor);
      }
      const ownedGroups = await query.get();
      const ownsSharedGroup = ownedGroups.docs.some((document) => {
        const group = document.data();
        return group.ownerId === uid &&
          Array.isArray(group.members) &&
          group.members.length > 1;
      });
      if (ownsSharedGroup) {
        const error = new Error(
          "Transfer ownership of every shared study before deletion.",
        );
        error.code = "failed-precondition";
        throw error;
      }
      return {
        done: ownedGroups.size < 50,
        processed: ownedGroups.size,
        cursor: ownedGroups.docs.at(-1)?.id ?? job.cursor ?? null,
      };
    },

    freeze: async () => {
      await db.doc(`users_private/${uid}`).set({
        deletionState: "deleting",
        updatedAt: Timestamp.now(),
      }, { merge: true });
      await ignoreMissingAuthUser(() => auth.updateUser(uid, {
        disabled: true,
      }));
      await ignoreMissingAuthUser(() => auth.revokeRefreshTokens(uid));
      return { done: true, processed: 1 };
    },

    memberships: async () => {
      const snapshot = await db.collection("groups")
        .where("members", "array-contains", uid)
        .limit(20)
        .get();
      for (const document of snapshot.docs) {
        const group = document.data();
        const members = Array.isArray(group.members) ? group.members : [];
        if (group.ownerId === uid && members.length > 1) {
          await ignoreMissingAuthUser(() => auth.updateUser(uid, {
            disabled: false,
          }));
          await db.doc(`users_private/${uid}`).set({
            deletionState: "blocked",
            updatedAt: Timestamp.now(),
          }, { merge: true });
          const error = new Error(
            "Transfer ownership of every shared study before deletion.",
          );
          error.code = "failed-precondition";
          throw error;
        }
        if (group.ownerId === uid) {
          const assets = await db.collection("managed_assets")
            .where("groupId", "==", document.id)
            .limit(50)
            .get();
          await deleteManagedAssetDocuments(assets.docs);
          if (assets.size === 50) {
            return { done: false, processed: assets.size };
          }
          await bucket.deleteFiles({
            prefix: `groups/${document.id}/`,
            force: true,
          });
          await db.recursiveDelete(document.ref);
          continue;
        }
        const batch = db.batch();
        batch.update(document.ref, {
          members: FieldValue.arrayRemove(uid),
          [`readingProgress.${uid}`]: FieldValue.delete(),
          [`userCompletedChapters.${uid}`]: FieldValue.delete(),
          [`unreadCounts.${uid}`]: FieldValue.delete(),
        });
        batch.delete(document.ref.collection("members").doc(uid));
        await batch.commit();
      }
      return { done: snapshot.size < 20, processed: snapshot.size };
    },

    insights: async () => {
      const snapshot = await db.collection("insights")
        .where("authorUid", "==", uid)
        .limit(1)
        .get();
      for (const document of snapshot.docs) {
        const [feedPointers, savedPointers] = await Promise.all([
          db.collectionGroup("insight_feed")
            .where("insightId", "==", document.id)
            .limit(400)
            .get(),
          db.collectionGroup("saved_insights")
            .where("insightId", "==", document.id)
            .limit(400)
            .get(),
        ]);
        const pointerBatch = db.batch();
        for (const pointer of [...feedPointers.docs, ...savedPointers.docs]) {
          pointerBatch.delete(pointer.ref);
        }
        if (!feedPointers.empty || !savedPointers.empty) {
          await pointerBatch.commit();
        }
        if (feedPointers.size === 400 || savedPointers.size === 400) {
          return {
            done: false,
            processed: feedPointers.size + savedPointers.size,
          };
        }
        await db.recursiveDelete(document.ref);
      }
      return { done: snapshot.empty, processed: snapshot.size };
    },

    messages: async () => {
      const snapshot = await db.collectionGroup("messages")
        .where("senderId", "==", uid)
        .limit(25)
        .get();
      if (!snapshot.empty) {
        await Promise.all(snapshot.docs.map(async (message) => {
          const groupId = message.ref.parent.parent?.id;
          if (!groupId) return;
          await bucket.deleteFiles({
            prefix: `groups/${groupId}/messages/${message.id}/`,
            force: true,
          });
          const assetIds = (message.data().parts ?? [])
            .map((part) => part?.assetId)
            .filter((assetId) => typeof assetId === "string");
          if (assetIds.length === 0) return;
          const assets = await db.getAll(
            ...assetIds.map((assetId) => db.doc(`managed_assets/${assetId}`)),
          );
          await deleteManagedAssetDocuments(
            assets.filter((asset) => asset.exists),
          );
        }));
        const batch = db.batch();
        for (const message of snapshot.docs) {
          batch.update(message.ref, {
            senderId: "deleted_account",
            senderName: "Deleted account",
            senderPhotoUrl: FieldValue.delete(),
            parts: [],
            isDeleted: true,
            deletedAt: Timestamp.now(),
          });
        }
        await batch.commit();
      }
      return { done: snapshot.size < 25, processed: snapshot.size };
    },

    comments: () => deleteDocuments(
      db.collectionGroup("comments").where("authorUid", "==", uid),
      100,
    ),
    reactions: () => deleteDocuments(
      db.collectionGroup("reactions").where("uid", "==", uid),
      100,
    ),
    blocks: () => deleteDocuments(
      db.collectionGroup("blocks").where("blockedUid", "==", uid),
      100,
    ),

    relationships: async () => {
      const snapshot = await db.collection(`users/${uid}/connections`)
        .limit(40)
        .get();
      for (const connection of snapshot.docs) {
        await db.runTransaction(async (transaction) => {
          const ownSnapshot = await transaction.get(connection.ref);
          if (!ownSnapshot.exists) return;
          const reciprocalRef = db.doc(
            `users/${connection.id}/connections/${uid}`,
          );
          const reciprocalPrivateRef = db.doc(
            `users_private/${connection.id}`,
          );
          const reciprocalPrivate = await transaction.get(
            reciprocalPrivateRef,
          );
          transaction.delete(connection.ref);
          transaction.delete(reciprocalRef);
          if (reciprocalPrivate.exists &&
              (reciprocalPrivate.data().connectionCount ?? 0) > 0) {
            transaction.update(reciprocalPrivateRef, {
              connectionCount: FieldValue.increment(-1),
              updatedAt: Timestamp.now(),
            });
          }
        });
      }
      return { done: snapshot.size < 40, processed: snapshot.size };
    },

    invites: () => deleteDocuments(
      db.collection("invites").where("createdBy", "==", uid),
      100,
    ),
    reports: async () => {
      const snapshot = await db.collection("reports")
        .where("reporterUid", "==", uid)
        .limit(100)
        .get();
      if (!snapshot.empty) {
        const batch = db.batch();
        for (const report of snapshot.docs) {
          batch.update(report.ref, {
            reporterUid: "deleted_account",
          });
        }
        await batch.commit();
      }
      return { done: snapshot.size < 100, processed: snapshot.size };
    },

    media: async () => {
      const assets = await db.collection("managed_assets")
        .where("ownerUid", "==", uid)
        .limit(50)
        .get();
      await deleteManagedAssetDocuments(assets.docs);
      if (assets.size === 50) {
        return { done: false, processed: assets.size };
      }
      await bucket.deleteFiles({ prefix: `users/${uid}/`, force: true });
      return { done: true, processed: assets.size };
    },
    ownedData: async () => {
      await Promise.all([
        db.recursiveDelete(db.doc(`users/${uid}`)),
        db.recursiveDelete(db.doc(`rate_limits/${uid}`)),
      ]);
      return { done: true, processed: 2 };
    },
    finalizeIdentity: async () => {
      await Promise.all([
        db.doc(`users_public/${uid}`).delete(),
        db.doc(`users_private/${uid}`).delete(),
      ]);
      await ignoreMissingAuthUser(() => auth.deleteUser(uid));
      return { done: true, processed: 3 };
    },
    verify: async () => {
      const [
        memberships,
        insights,
        messages,
        comments,
        reactions,
        blocks,
        connections,
        invites,
        reports,
        assets,
        ownedUser,
        rateLimit,
        publicProfile,
        privateProfile,
      ] = await Promise.all([
        db.collection("groups").where("members", "array-contains", uid)
          .limit(1).get(),
        db.collection("insights").where("authorUid", "==", uid).limit(1).get(),
        db.collectionGroup("messages").where("senderId", "==", uid)
          .limit(1).get(),
        db.collectionGroup("comments").where("authorUid", "==", uid)
          .limit(1).get(),
        db.collectionGroup("reactions").where("uid", "==", uid).limit(1).get(),
        db.collectionGroup("blocks").where("blockedUid", "==", uid)
          .limit(1).get(),
        db.collection(`users/${uid}/connections`).limit(1).get(),
        db.collection("invites").where("createdBy", "==", uid).limit(1).get(),
        db.collection("reports").where("reporterUid", "==", uid).limit(1).get(),
        db.collection("managed_assets").where("ownerUid", "==", uid)
          .limit(1).get(),
        db.doc(`users/${uid}`).get(),
        db.doc(`rate_limits/${uid}`).get(),
        db.doc(`users_public/${uid}`).get(),
        db.doc(`users_private/${uid}`).get(),
      ]);
      const restartPhase = [
        ["memberships", memberships],
        ["insights", insights],
        ["messages", messages],
        ["comments", comments],
        ["reactions", reactions],
        ["blocks", blocks],
        ["relationships", connections],
        ["invites", invites],
        ["reports", reports],
        ["media", assets],
      ].find(([, snapshot]) => !snapshot.empty)?.[0];
      if (restartPhase) {
        return { done: false, processed: 0, nextPhase: restartPhase };
      }
      if (publicProfile.exists || privateProfile.exists) {
        return {
          done: false,
          processed: 0,
          nextPhase: "finalizeIdentity",
        };
      }
      if (ownedUser.exists || rateLimit.exists) {
        return { done: false, processed: 0, nextPhase: "ownedData" };
      }
      try {
        await auth.getUser(uid);
        return {
          done: false,
          processed: 0,
          nextPhase: "finalizeIdentity",
        };
      } catch (error) {
        if (error?.code !== "auth/user-not-found") throw error;
      }
      return { done: true, processed: 0 };
    },
  };
}

module.exports = {
  ACCOUNT_DELETION_PHASES,
  createAccountDeletionHandlers,
  processDeletionStep,
};
