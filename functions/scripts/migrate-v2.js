#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
const {
  canonicalInvitePath,
  deriveGroupMigration,
  deriveInsightMigration,
  deriveInviteMigration,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
  validateCanonicalDocument,
  validateManagedMessageAsset,
} = require("../lib/migration");
const {
  rollbackMigration,
  runMigration,
} = require("../lib/migration_runner");

const DEFAULT_PAGE_SIZE = 100;
const DEFAULT_BATCH_SIZE = 200;
const DEFAULT_CONCURRENCY = 4;
const RUN_COLLECTION = "_migration_runs";

function argumentValue(argv, name) {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : null;
}

function integerArgument(argv, name, fallback) {
  const value = argumentValue(argv, name);
  if (value === null) return fallback;
  if (!/^\d+$/.test(value)) throw new Error(`${name} must be an integer`);
  return Number(value);
}

function parseArguments(argv) {
  const runId = argumentValue(argv, "--run-id")
    ?? `v2-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(runId)) {
    throw new Error("--run-id must use 1-128 letters, numbers, _ or -");
  }
  const reportPath = path.resolve(
    argumentValue(argv, "--report") ?? `migration-v2-${runId}-report.json`,
  );
  return {
    apply: argv.includes("--apply"),
    rehearse: argv.includes("--rehearse"),
    projectId: argumentValue(argv, "--project"),
    runId,
    rollbackArtifact: argumentValue(argv, "--rollback"),
    reportPath,
    artifactPath: path.resolve(
      argumentValue(argv, "--artifact")
        ?? `migration-v2-${runId}-before-images.jsonl`,
    ),
    checkpointPath: path.resolve(
      argumentValue(argv, "--checkpoint")
        ?? `migration-v2-${runId}-checkpoint.json`,
    ),
    pageSize: integerArgument(
      argv,
      "--page-size",
      DEFAULT_PAGE_SIZE,
    ),
    batchSize: integerArgument(
      argv,
      "--batch-size",
      DEFAULT_BATCH_SIZE,
    ),
    concurrency: integerArgument(
      argv,
      "--concurrency",
      DEFAULT_CONCURRENCY,
    ),
  };
}

function writeJsonAtomic(filePath, value, mode = 0o600) {
  const resolved = path.resolve(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  const temporary = `${resolved}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode,
  });
  fs.renameSync(temporary, resolved);
  try {
    fs.chmodSync(resolved, mode);
  } catch {
    // Windows ACLs govern access when chmod is not meaningful.
  }
}

function encodeFirestore(value) {
  if (value === null || value === undefined) return value;
  if (value instanceof admin.firestore.Timestamp) {
    return { $firestoreType: "timestamp", millis: value.toMillis() };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return {
      $firestoreType: "bytes",
      base64: Buffer.from(value).toString("base64"),
    };
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {
      $firestoreType: "geopoint",
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return { $firestoreType: "reference", path: value.path };
  }
  if (Array.isArray(value)) return value.map(encodeFirestore);
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        encodeFirestore(nested),
      ]),
    );
  }
  return value;
}

function decodeFirestore(value, db) {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) {
    return value.map((nested) => decodeFirestore(nested, db));
  }
  if (typeof value !== "object") return value;
  if (value.$firestoreType === "timestamp") {
    return admin.firestore.Timestamp.fromMillis(value.millis);
  }
  if (value.$firestoreType === "bytes") {
    return Buffer.from(value.base64, "base64");
  }
  if (value.$firestoreType === "geopoint") {
    return new admin.firestore.GeoPoint(value.latitude, value.longitude);
  }
  if (value.$firestoreType === "reference") return db.doc(value.path);
  return Object.fromEntries(
    Object.entries(value).map(([key, nested]) => [
      key,
      decodeFirestore(nested, db),
    ]),
  );
}

function loadJsonLines(filePath) {
  if (!fs.existsSync(filePath)) return [];
  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function appendJsonLine(filePath, value) {
  const resolved = path.resolve(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.appendFileSync(resolved, `${JSON.stringify(value)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  try {
    fs.chmodSync(resolved, 0o600);
  } catch {
    // Windows ACLs govern access when chmod is not meaningful.
  }
}

function firestoreQuery(db, phase) {
  switch (phase) {
    case "users":
    case "groups":
    case "insights":
    case "invites":
    case "group_invites":
      return db.collection(phase);
    case "notes":
    case "saved_insights":
    case "messages":
      return db.collectionGroup(phase);
    default:
      throw new Error(`Unknown migration phase: ${phase}`);
  }
}

function createFirestoreAdapter({
  db,
  apply,
  artifactPath,
  checkpointPath,
}) {
  const existingArtifactEntries = loadJsonLines(artifactPath);
  const capturedPaths = new Set(
    existingArtifactEntries.map((entry) => entry.path),
  );
  const lockPath = `${checkpointPath}.lock`;
  return {
    async acquireLease(runId, owner, expiresAtMillis) {
      if (!apply) {
        try {
          fs.writeFileSync(lockPath, JSON.stringify({
            runId,
            owner,
            expiresAtMillis,
          }), { encoding: "utf8", flag: "wx", mode: 0o600 });
          return;
        } catch (error) {
          if (error.code !== "EEXIST") throw error;
          const existing = JSON.parse(fs.readFileSync(lockPath, "utf8"));
          if (existing.expiresAtMillis > Date.now()
            && existing.owner !== owner) {
            throw new Error("migration run lease is already held");
          }
          fs.writeFileSync(lockPath, JSON.stringify({
            runId,
            owner,
            expiresAtMillis,
          }), { encoding: "utf8", mode: 0o600 });
          return;
        }
      }
      const reference = db.doc(`${RUN_COLLECTION}/${runId}`);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        const existing = snapshot.exists ? snapshot.data() : {};
        if (existing._leaseOwner && existing._leaseOwner !== owner
          && existing._leaseExpiresAtMillis > Date.now()) {
          throw new Error("migration run lease is already held");
        }
        transaction.set(reference, {
          _leaseOwner: owner,
          _leaseExpiresAtMillis: expiresAtMillis,
        }, { merge: true });
      });
    },
    async renewLease(runId, owner, expiresAtMillis) {
      if (!apply) {
        const existing = JSON.parse(fs.readFileSync(lockPath, "utf8"));
        if (existing.owner !== owner || existing.runId !== runId) {
          throw new Error("migration run lease was lost");
        }
        fs.writeFileSync(lockPath, JSON.stringify({
          runId,
          owner,
          expiresAtMillis,
        }), { encoding: "utf8", mode: 0o600 });
        return;
      }
      const reference = db.doc(`${RUN_COLLECTION}/${runId}`);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (!snapshot.exists || snapshot.data()._leaseOwner !== owner) {
          throw new Error("migration run lease was lost");
        }
        transaction.set(reference, {
          _leaseExpiresAtMillis: expiresAtMillis,
        }, { merge: true });
      });
    },
    async releaseLease(runId, owner) {
      if (!apply) {
        if (!fs.existsSync(lockPath)) return;
        const existing = JSON.parse(fs.readFileSync(lockPath, "utf8"));
        if (existing.owner === owner && existing.runId === runId) {
          fs.unlinkSync(lockPath);
        }
        return;
      }
      const reference = db.doc(`${RUN_COLLECTION}/${runId}`);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (snapshot.exists && snapshot.data()._leaseOwner === owner) {
          transaction.set(reference, {
            _leaseOwner: admin.firestore.FieldValue.delete(),
            _leaseExpiresAtMillis: admin.firestore.FieldValue.delete(),
          }, { merge: true });
        }
      });
    },
    async loadRun(runId) {
      if (!apply) {
        if (!fs.existsSync(checkpointPath)) return null;
        const checkpoint = JSON.parse(fs.readFileSync(
          checkpointPath,
          "utf8",
        ));
        return checkpoint.runId === runId ? checkpoint : null;
      }
      const snapshot = await db.doc(`${RUN_COLLECTION}/${runId}`).get();
      if (!snapshot.exists) return null;
      const state = snapshot.data();
      delete state._leaseOwner;
      delete state._leaseExpiresAtMillis;
      return state;
    },
    async saveRun(runId, state) {
      if (!apply) {
        writeJsonAtomic(checkpointPath, state);
        return;
      }
      await db.doc(`${RUN_COLLECTION}/${runId}`).set(state, { merge: true });
    },
    async fetchPage(phase, afterPath, limit) {
      let query = firestoreQuery(db, phase)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(limit);
      if (afterPath) query = query.startAfter(db.doc(afterPath));
      const snapshot = await query.get();
      return snapshot.docs.map((document) => ({
        id: document.ref.path,
        path: document.ref.path,
        data: document.data(),
        reference: document.ref,
      }));
    },
    async captureBeforeImages(runId, operations) {
      if (existingArtifactEntries.some((entry) => entry.runId !== runId)) {
        throw new Error(
          "Before-image artifact belongs to a different migration run",
        );
      }
      const uncaptured = operations.filter(
        (operation) => !capturedPaths.has(operation.path),
      );
      if (uncaptured.length === 0) return;
      const snapshots = await db.getAll(
        ...uncaptured.map((operation) => db.doc(operation.path)),
      );
      for (let index = 0; index < uncaptured.length; index += 1) {
        const operation = uncaptured[index];
        const snapshot = snapshots[index];
        appendJsonLine(artifactPath, {
          schemaVersion: 1,
          runId,
          path: operation.path,
          existed: snapshot.exists,
          data: snapshot.exists
            ? encodeFirestore(snapshot.data())
            : null,
        });
        capturedPaths.add(operation.path);
      }
    },
    async commit(operations) {
      const batch = db.batch();
      for (const operation of operations) {
        const reference = db.doc(operation.path);
        if (operation.delete) batch.delete(reference);
        else batch.set(reference, operation.data);
      }
      await batch.commit();
    },
    async commitWithCheckpoint(runId, operations, state) {
      const batch = db.batch();
      for (const operation of operations) {
        const reference = db.doc(operation.path);
        if (operation.delete) batch.delete(reference);
        else batch.set(reference, operation.data);
      }
      batch.set(
        db.doc(`${RUN_COLLECTION}/${runId}`),
        state,
        { merge: true },
      );
      await batch.commit();
    },
    async readBeforeImages(runId) {
      const entries = loadJsonLines(artifactPath);
      if (entries.some((entry) => entry.runId !== runId)) {
        throw new Error("Rollback artifact contains a different run ID");
      }
      return entries.map((entry) => ({
        path: entry.path,
        existed: entry.existed,
        data: entry.existed ? decodeFirestore(entry.data, db) : null,
      }));
    },
  };
}

function issueResult(issue, documentPath) {
  return {
    operations: [],
    issues: [{
      ...issue,
      document: issue.document ?? documentPath,
    }],
  };
}

function validatedOperation(kind, pathValue, data) {
  const fields = validateCanonicalDocument(kind, data);
  return fields.length
    ? issueResult({
        code: "canonical-validation-failed",
        fields,
      }, pathValue)
    : { operations: [{ path: pathValue, data }], issues: [] };
}

function extractOwnerPath(documentPath, collectionName) {
  const segments = documentPath.split("/");
  const collectionIndex = segments.lastIndexOf(collectionName);
  if (collectionIndex !== 2 || segments[0] !== "users") return null;
  return segments[1];
}

function extractGroupPath(documentPath) {
  const segments = documentPath.split("/");
  return segments.length === 4
    && segments[0] === "groups"
    && segments[2] === "messages"
    ? { groupId: segments[1], messageId: segments[3] }
    : null;
}

function migrationPhases(db) {
  const projectedPublicProfiles = new Map();
  async function publicProfile(uid) {
    if (projectedPublicProfiles.has(uid)) {
      return projectedPublicProfiles.get(uid);
    }
    const snapshot = await db.doc(`users_public/${uid}`).get();
    return snapshot.exists ? snapshot.data() : null;
  }
  return [
    {
      name: "users",
      async transform(document, context) {
        const timestamp = admin.firestore.Timestamp.fromMillis(
          context.startedAtMillis,
        );
        const [publicSnapshot, privateSnapshot] = await db.getAll(
          db.doc(`users_public/${document.reference.id}`),
          db.doc(`users_private/${document.reference.id}`),
        );
        const combinedSource = {
          ...document.data,
          ...(privateSnapshot.exists ? privateSnapshot.data() : {}),
          ...(publicSnapshot.exists ? publicSnapshot.data() : {}),
        };
        const derived = deriveUserDocuments(
          document.reference.id,
          combinedSource,
          timestamp,
        );
        const publicIssues = validateCanonicalDocument(
          "publicUser",
          derived.public,
        );
        const privateIssues = validateCanonicalDocument(
          "privateUser",
          derived.private,
        );
        if (publicIssues.length || privateIssues.length) {
          return issueResult({
            code: "canonical-validation-failed",
            fields: [...publicIssues, ...privateIssues],
          }, document.path);
        }
        projectedPublicProfiles.set(document.reference.id, derived.public);
        const connectionCountSnapshot = await document.reference
          .collection("connections")
          .count()
          .get();
        const connectionCount = connectionCountSnapshot.data().count;
        if (connectionCount > 500) {
          return issueResult({
            code: "connection-limit-exceeded",
            fields: ["connectionCount"],
          }, document.path);
        }
        derived.private.connectionCount = connectionCount;
        const operations = [
          {
            path: `users_public/${document.reference.id}`,
            data: derived.public,
          },
          {
            path: `users_private/${document.reference.id}`,
            data: derived.private,
          },
        ];
        if (derived.legacyFcmToken) {
          const deviceId = crypto.createHash("sha256")
            .update(derived.legacyFcmToken)
            .digest("hex")
            .slice(0, 32);
          operations.push({
            path: `users/${document.reference.id}/devices/${deviceId}`,
            data: {
              token: derived.legacyFcmToken,
              platform: "android",
              notificationsEnabled: true,
              messageNotifications: true,
              insightNotifications: true,
              previewContent: false,
              createdAt: timestamp,
              updatedAt: timestamp,
            },
          });
        }
        return { operations, issues: [] };
      },
    },
    {
      name: "notes",
      transform(document, context) {
        const uid = extractOwnerPath(document.path, "notes");
        if (!uid) {
          return issueResult({
            code: "unexpected-note-path",
            fields: ["path"],
          }, document.path);
        }
        const migration = deriveNoteMigration(
          uid,
          document.data,
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
        );
        return migration.issue
          ? issueResult(migration.issue, document.path)
          : validatedOperation("note", document.path, migration);
      },
    },
    {
      name: "saved_insights",
      transform(document, context) {
        const uid = extractOwnerPath(document.path, "saved_insights");
        if (!uid) {
          return issueResult({
            code: "unexpected-saved-insight-path",
            fields: ["path"],
          }, document.path);
        }
        return {
          operations: [{
            path: document.path,
            data: deriveSavedInsightMigration(
              document.reference.id,
              document.data,
              admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
            ),
          }],
          issues: [],
        };
      },
    },
    {
      name: "groups",
      transform(document, context) {
        const migration = deriveGroupMigration(
          document.reference.id,
          document.data,
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
        );
        if (migration.issue) return issueResult(migration.issue, document.path);
        return {
          operations: [
            { path: document.path, data: migration.group },
            ...migration.members.map((member) => ({
              path: `${document.path}/members/${member.uid}`,
              data: member,
            })),
          ],
          issues: [],
        };
      },
    },
    {
      name: "messages",
      async transform(document, context) {
        const identity = extractGroupPath(document.path);
        if (!identity) {
          return issueResult({
            code: "unexpected-message-path",
            fields: ["path"],
          }, document.path);
        }
        const senderId = typeof (
          document.data.senderId
          ?? document.data.authorUid
          ?? document.data.userId
        ) === "string"
          ? (
              document.data.senderId
              ?? document.data.authorUid
              ?? document.data.userId
            ).trim()
          : "";
        if (!senderId) {
          return issueResult({
            code: "missing-message-sender",
            fields: ["senderId"],
          }, document.path);
        }
        const profile = await publicProfile(senderId);
        if (!profile) {
          return issueResult({
            code: "missing-canonical-public-profile",
            fields: ["senderId"],
          }, document.path);
        }
        const migration = deriveMessageMigration(
          identity.messageId,
          {
            ...document.data,
            senderName: profile.displayName,
            senderPhotoUrl: profile.photoUrl ?? "",
            senderPhotoURL: "",
            authorPhotoUrl: "",
          },
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
          { groupId: identity.groupId },
        );
        if (migration.issue) return issueResult(migration.issue, document.path);
        const mediaParts = migration.message.parts.filter(
          (part) => ["voice", "image"].includes(part.type),
        );
        if (mediaParts.length) {
          const assetSnapshots = await db.getAll(
            ...mediaParts.map((part) => db.doc(
              `managed_assets/${part.assetId}`,
            )),
          );
          const assetIssues = mediaParts.flatMap((part, index) =>
            validateManagedMessageAsset(
              part,
              assetSnapshots[index].exists
                ? assetSnapshots[index].data()
                : null,
              {
                ...identity,
                senderId: migration.message.senderId,
              },
            ),
          );
          if (assetIssues.length) {
            return issueResult({
              code: "managed-asset-invariant-failed",
              fields: [...new Set(assetIssues)],
            }, document.path);
          }
        }
        return validatedOperation(
          "message",
          document.path,
          migration.message,
        );
      },
    },
    {
      name: "insights",
      async transform(document, context) {
        const authorUid = typeof (
          document.data.authorUid
          ?? document.data.userId
          ?? document.data.authorId
        ) === "string"
          ? (
              document.data.authorUid
              ?? document.data.userId
              ?? document.data.authorId
            ).trim()
          : "";
        if (!authorUid) {
          return issueResult({
            code: "invalid-insight",
            fields: ["authorUid"],
          }, document.path);
        }
        const profile = await publicProfile(authorUid);
        if (!profile) {
          return issueResult({
            code: "missing-canonical-public-profile",
            fields: ["authorUid"],
          }, document.path);
        }
        const migration = deriveInsightMigration(
          {
            ...document.data,
            authorName: profile.displayName,
            userName: profile.displayName,
            authorPhotoUrl: profile.photoUrl ?? "",
            userPhotoUrl: "",
            userPhotoURL: "",
          },
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
          { fromMillis: admin.firestore.Timestamp.fromMillis },
        );
        return migration.issue
          ? issueResult(migration.issue, document.path)
          : validatedOperation("insight", document.path, migration.insight);
      },
    },
    {
      name: "invites",
      async transform(document, context) {
        const migration = deriveInviteMigration(
          document.reference.id,
          document.data,
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
        );
        if (migration.issue) return issueResult(migration.issue, document.path);
        const targetPath = canonicalInvitePath(migration.inviteId);
        const validation = validateCanonicalDocument(
          "invite",
          migration.invite,
        );
        if (validation.length) {
          return issueResult({
            code: "canonical-validation-failed",
            fields: validation,
          }, document.path);
        }
        if (targetPath === document.path) {
          return {
            operations: [{ path: targetPath, data: migration.invite }],
            issues: [],
          };
        }
        const target = await db.doc(targetPath).get();
        if (target.exists) {
          return issueResult({
            code: "invite-destination-exists",
            fields: ["inviteId"],
          }, document.path);
        }
        return {
          operations: [
            { path: targetPath, data: migration.invite },
            { path: document.path, delete: true },
          ],
          issues: [],
        };
      },
    },
    {
      name: "group_invites",
      async transform(document, context) {
        const migration = deriveInviteMigration(
          document.reference.id,
          document.data,
          admin.firestore.Timestamp.fromMillis(context.startedAtMillis),
        );
        if (migration.issue) return issueResult(migration.issue, document.path);
        const targetPath = canonicalInvitePath(migration.inviteId);
        const existingTarget = await db.doc(targetPath).get();
        if (existingTarget.exists) {
          return issueResult({
            code: "invite-destination-exists",
            fields: ["inviteId"],
          }, document.path);
        }
        return {
          operations: [
            {
              path: targetPath,
              data: migration.invite,
            },
            { path: document.path, delete: true },
          ],
          issues: [],
        };
      },
    },
  ];
}

function rehearsalAdapter(seed, interruptAtCommit = null) {
  const documents = structuredClone(seed);
  const runs = new Map();
  const beforeImages = new Map();
  let commitCount = 0;
  return {
    documents,
    async loadRun(runId) {
      return runs.get(runId) ?? null;
    },
    async saveRun(runId, state) {
      runs.set(runId, structuredClone(state));
    },
    async fetchPage(phase, cursor, limit) {
      return Object.entries(documents)
        .filter(([documentPath]) => documentPath.startsWith(`${phase}/`))
        .map(([documentPath, data]) => ({
          id: documentPath,
          path: documentPath,
          data: structuredClone(data),
        }))
        .filter((document) => !cursor || document.id > cursor)
        .sort((left, right) => left.id.localeCompare(right.id))
        .slice(0, limit);
    },
    async captureBeforeImages(runId, operations) {
      const artifact = beforeImages.get(runId) ?? new Map();
      for (const operation of operations) {
        if (!artifact.has(operation.path)) {
          artifact.set(operation.path, Object.hasOwn(documents, operation.path)
            ? structuredClone(documents[operation.path])
            : null);
        }
      }
      beforeImages.set(runId, artifact);
    },
    async commit(operations) {
      if (commitCount === interruptAtCommit) {
        interruptAtCommit = null;
        throw new Error("rehearsed interruption");
      }
      for (const operation of operations) {
        if (operation.delete) delete documents[operation.path];
        else documents[operation.path] = structuredClone(operation.data);
      }
      commitCount += 1;
    },
    async commitWithCheckpoint(runId, operations, state) {
      await this.commit(operations);
      runs.set(runId, structuredClone(state));
    },
    async readBeforeImages(runId) {
      return [...(beforeImages.get(runId) ?? new Map()).entries()].map(
        ([documentPath, data]) => ({
          path: documentPath,
          existed: data !== null,
          data,
        }),
      );
    },
  };
}

async function runRehearsal(options) {
  const seed = {
    "legacy/a": { privateValue: "one" },
    "legacy/b": { privateValue: "two" },
    "legacy/c": { privateValue: "three" },
  };
  const original = structuredClone(seed);
  const adapter = rehearsalAdapter(seed, 1);
  const phases = [{
    name: "legacy",
    transform(document) {
      return {
        operations: [
          {
            path: document.path,
            data: { schemaVersion: 2, migrated: true },
          },
          {
            path: `canonical/${document.path.split("/").at(-1)}`,
            data: { schemaVersion: 2 },
          },
        ],
        issues: [],
      };
    },
  }];
  let interrupted = false;
  try {
    await runMigration({
      adapter,
      phases,
      runId: options.runId,
      apply: true,
      pageSize: 2,
      batchSize: 2,
      concurrency: 2,
      nowMillis: 1000,
    });
  } catch (error) {
    if (!/rehearsed interruption/.test(error.message)) throw error;
    interrupted = true;
  }
  const resumed = await runMigration({
    adapter,
    phases,
    runId: options.runId,
    apply: true,
    pageSize: 2,
    batchSize: 2,
    concurrency: 2,
    nowMillis: 2000,
  });
  const rollback = await rollbackMigration({
    adapter,
    runId: options.runId,
    batchSize: 2,
  });
  const restored = JSON.stringify(adapter.documents) === JSON.stringify(
    original,
  );
  const report = {
    schemaVersion: 1,
    mode: "rehearsal",
    runId: options.runId,
    interruptionObserved: interrupted,
    resumeCompleted: resumed.status === "complete",
    rollback,
    rollbackRestoredExactSeed: restored,
  };
  writeJsonAtomic(options.reportPath, report);
  if (!interrupted || resumed.status !== "complete" || !restored) {
    throw new Error("Migration rehearsal did not satisfy its contract");
  }
  return report;
}

async function main(argv = process.argv.slice(2)) {
  const options = parseArguments(argv);
  if (options.rehearse) {
    const report = await runRehearsal(options);
    process.stdout.write(
      `Rehearsal passed for ${report.runId}; report: `
      + `${options.reportPath}\n`,
    );
    return;
  }
  if (!options.projectId) {
    throw new Error(
      "Provide --project <firebase-project-id>. Dry-run is the default.",
    );
  }
  if (options.rollbackArtifact && !options.apply) {
    throw new Error("Rollback changes data and requires --apply");
  }
  admin.initializeApp({ projectId: options.projectId });
  const db = admin.firestore();
  const adapter = createFirestoreAdapter({
    db,
    apply: options.apply,
    artifactPath: options.rollbackArtifact
      ? path.resolve(options.rollbackArtifact)
      : options.artifactPath,
    checkpointPath: options.checkpointPath,
  });

  if (options.rollbackArtifact) {
    const rollback = await rollbackMigration({
      adapter,
      runId: options.runId,
      batchSize: options.batchSize,
    });
    writeJsonAtomic(options.reportPath, {
      schemaVersion: 1,
      mode: "rollback",
      projectId: options.projectId,
      ...rollback,
    });
    process.stdout.write(
      `Rollback restored ${rollback.restored} and deleted `
      + `${rollback.deleted}; report: ${options.reportPath}\n`,
    );
    return;
  }

  const summary = await runMigration({
    adapter,
    phases: migrationPhases(db),
    runId: options.runId,
    apply: options.apply,
    pageSize: options.pageSize,
    batchSize: options.batchSize,
    concurrency: options.concurrency,
  });
  const report = {
    ...summary,
    projectId: options.projectId,
    canonicalInviteCollection: "invites",
    rollbackArtifact: options.apply
      ? {
          pathHash: crypto.createHash("sha256")
            .update(options.artifactPath)
            .digest("hex"),
          retainedLocally: true,
        }
      : null,
    guarantees: [
      "Document pages are ordered by full Firestore document path.",
      "Canonical replacements remove rule-disallowed legacy fields.",
      "No raw document content is emitted in the summary.",
      "Apply mode captures first before-images before writes.",
      "Legacy group_invites are moved to canonical invites with rollback data.",
    ],
  };
  writeJsonAtomic(options.reportPath, report);
  process.stdout.write(
    `${options.apply ? "Applied" : "Planned"} `
    + `${summary.counts.proposedWrites} writes in run ${options.runId}; `
    + `${summary.counts.issues} issue(s). Report: ${options.reportPath}\n`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  createFirestoreAdapter,
  decodeFirestore,
  encodeFirestore,
  main,
  migrationPhases,
  parseArguments,
  runRehearsal,
};
