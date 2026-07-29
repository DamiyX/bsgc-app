#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const admin = require("firebase-admin");
const {
  deriveGroupMigration,
  deriveInsightMigration,
  deriveMessageMigration,
  deriveNoteMigration,
  deriveSavedInsightMigration,
  deriveUserDocuments,
} = require("../lib/migration");

function parseArguments(argv) {
  const apply = argv.includes("--apply");
  const projectIndex = argv.indexOf("--project");
  const reportIndex = argv.indexOf("--report");
  return {
    apply,
    projectId: projectIndex >= 0 ? argv[projectIndex + 1] : null,
    reportPath: reportIndex >= 0
      ? argv[reportIndex + 1]
      : path.resolve(process.cwd(), "migration-v2-report.json"),
  };
}

async function collectDocuments(query, pageSize = 250) {
  const documents = [];
  let cursor = null;
  while (true) {
    let pageQuery = query
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    documents.push(...page.docs);
    if (page.size < pageSize) break;
    cursor = page.docs[page.docs.length - 1];
  }
  return documents;
}

async function commitOperations(db, operations, apply) {
  if (!apply) return;
  for (let index = 0; index < operations.length; index += 400) {
    const batch = db.batch();
    for (const operation of operations.slice(index, index + 400)) {
      batch.set(operation.reference, operation.data, { merge: true });
    }
    await batch.commit();
  }
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (!options.projectId) {
    throw new Error(
      "Provide --project <firebase-project-id>. Dry-run is the default; "
      + "add --apply only after reviewing the report.",
    );
  }

  admin.initializeApp({ projectId: options.projectId });
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const operations = [];
  const issues = [];
  const counts = {
    users: 0,
    publicUsers: 0,
    privateUsers: 0,
    deviceTokens: 0,
    notes: 0,
    savedInsightPointers: 0,
    connections: 0,
    groups: 0,
    groupMembers: 0,
    messages: 0,
    insights: 0,
  };

  const userDocuments = await collectDocuments(db.collection("users"));
  for (const userDocument of userDocuments) {
    counts.users += 1;
    const derived = deriveUserDocuments(
      userDocument.id,
      userDocument.data(),
      now,
    );
    operations.push({
      reference: db.doc(`users_public/${userDocument.id}`),
      data: derived.public,
    });
    operations.push({
      reference: db.doc(`users_private/${userDocument.id}`),
      data: derived.private,
    });
    counts.publicUsers += 1;
    counts.privateUsers += 1;

    if (derived.legacyFcmToken) {
      const deviceId = crypto
        .createHash("sha256")
        .update(derived.legacyFcmToken)
        .digest("hex")
        .slice(0, 32);
      operations.push({
        reference: db.doc(`users/${userDocument.id}/devices/${deviceId}`),
        data: {
          token: derived.legacyFcmToken,
          platform: "android",
          notificationsEnabled: true,
          messageNotifications: true,
          insightNotifications: true,
          previewContent: false,
          createdAt: now,
          updatedAt: now,
        },
      });
      counts.deviceTokens += 1;
    }

    const [
      noteDocuments,
      savedInsightDocuments,
      connectionDocuments,
    ] = await Promise.all([
      collectDocuments(userDocument.ref.collection("notes")),
      collectDocuments(userDocument.ref.collection("saved_insights")),
      collectDocuments(userDocument.ref.collection("connections")),
    ]);
    operations.push({
      reference: db.doc(`users_private/${userDocument.id}`),
      data: {
        connectionCount: Math.min(connectionDocuments.length, 500),
        updatedAt: now,
      },
    });
    if (connectionDocuments.length > 500) {
      issues.push({
        document: `users/${userDocument.id}/connections`,
        code: "connection-limit-exceeded",
        message:
          "Account has more than 500 contacts and requires manual review.",
      });
    }
    counts.connections += connectionDocuments.length;
    for (const noteDocument of noteDocuments) {
      const noteMigration = deriveNoteMigration(
        userDocument.id,
        noteDocument.data(),
        now,
      );
      if (noteMigration.issue) {
        issues.push({
          document: noteDocument.ref.path,
          ...noteMigration.issue,
        });
        continue;
      }
      operations.push({
        reference: noteDocument.ref,
        data: noteMigration,
      });
      counts.notes += 1;
    }
    for (const savedDocument of savedInsightDocuments) {
      operations.push({
        reference: savedDocument.ref,
        data: deriveSavedInsightMigration(
          savedDocument.id,
          savedDocument.data(),
          now,
        ),
      });
      counts.savedInsightPointers += 1;
    }
  }

  const groupDocuments = await collectDocuments(db.collection("groups"));
  for (const groupDocument of groupDocuments) {
    const migration = deriveGroupMigration(
      groupDocument.id,
      groupDocument.data(),
      now,
    );
    if (migration.issue) {
      issues.push(migration.issue);
      continue;
    }

    operations.push({
      reference: groupDocument.ref,
      data: migration.group,
    });
    counts.groups += 1;
    for (const member of migration.members) {
      operations.push({
        reference: groupDocument.ref.collection("members").doc(member.uid),
        data: member,
      });
      counts.groupMembers += 1;
    }

    const messageDocuments = await collectDocuments(
      groupDocument.ref.collection("messages"),
    );
    for (const messageDocument of messageDocuments) {
      const messageMigration = deriveMessageMigration(
        messageDocument.id,
        messageDocument.data(),
        now,
      );
      if (messageMigration.issue) {
        issues.push({
          document: messageDocument.ref.path,
          ...messageMigration.issue,
        });
        continue;
      }
      operations.push({
        reference: messageDocument.ref,
        data: messageMigration.message,
      });
      counts.messages += 1;
    }
  }

  const insightDocuments = await collectDocuments(db.collection("insights"));
  for (const insightDocument of insightDocuments) {
    operations.push({
      reference: insightDocument.ref,
      data: deriveInsightMigration(insightDocument.data(), now),
    });
    counts.insights += 1;
  }

  const report = {
    schemaVersion: 1,
    mode: options.apply ? "apply" : "dry-run",
    projectId: options.projectId,
    generatedAt: new Date().toISOString(),
    proposedWriteCount: operations.length,
    counts,
    issues,
    guarantees: [
      "No legacy document or field is deleted by this migration.",
      "Every write is an idempotent merge.",
      "Groups without a safely inferable owner are reported and skipped.",
      "Legacy referral data is not converted into Insight-viewing access.",
      "Raw invitation tokens are never written.",
      "Inline legacy voice and image data is reported and skipped until moved to Storage.",
    ],
  };

  fs.writeFileSync(
    path.resolve(options.reportPath),
    `${JSON.stringify(report, null, 2)}\n`,
    "utf8",
  );
  await commitOperations(db, operations, options.apply);

  process.stdout.write(
    `${options.apply ? "Applied" : "Planned"} ${operations.length} writes; `
    + `${issues.length} issue(s). Report: ${path.resolve(options.reportPath)}\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.stack ?? error}\n`);
  process.exitCode = 1;
});
