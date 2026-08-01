const { after, before, beforeEach, describe, test } = require("node:test");
const path = require("node:path");
const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const PROJECT_ID = "demo-braid-rules";
const ROOT = path.resolve(__dirname, "../../..");
const RULES = fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8");

let testEnv;

function now() {
  return Timestamp.fromDate(new Date());
}

function future(days = 3) {
  return Timestamp.fromDate(new Date(Date.now() + days * 24 * 60 * 60 * 1000));
}

function groupData(overrides = {}) {
  return {
    schemaVersion: 2,
    ownerId: "owner",
    name: "Morning Study",
    members: ["owner", "member"],
    readingProgress: { owner: 0, member: 0 },
    userCompletedChapters: { owner: [], member: [] },
    unreadCounts: { owner: 0, member: 0 },
    pinnedScripture: "",
    description: "A private study group",
    createdAt: now(),
    groupType: "Bible",
    studyBook: "John",
    totalChapters: 21,
    lifecycle: "active",
    extensionCount: 0,
    ...overrides,
  };
}

function insightData(overrides = {}) {
  return {
    schemaVersion: 2,
    authorUid: "author",
    authorName: "Author",
    title: "Grace",
    body: "A reflection about grace.",
    themeId: "theme_0",
    audience: "contacts",
    status: "active",
    createdAt: now(),
    updatedAt: now(),
    expiresAt: future(),
    ...overrides,
  };
}

async function seedFirestore() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users/owner"), {
        uid: "owner",
        displayName: "Owner",
      }),
      setDoc(doc(db, "users_private/owner"), {
        schemaVersion: 2,
        uid: "owner",
        phoneNumbers: ["+2348000000000"],
        phoneVerified: false,
        createdAt: now(),
        updatedAt: now(),
      }),
      setDoc(doc(db, "users_public/owner"), {
        schemaVersion: 2,
        uid: "owner",
        displayName: "Owner",
        createdAt: now(),
        updatedAt: now(),
      }),
      setDoc(doc(db, "users_public/member"), {
        schemaVersion: 2,
        uid: "member",
        displayName: "Member",
        photoUrl: "https://example.com/member.jpg",
        createdAt: now(),
        updatedAt: now(),
      }),
      setDoc(doc(db, "account_deletion_jobs/owner"), {
        schemaVersion: 1,
        uid: "owner",
        status: "queued",
        phase: "preflight",
        requestedAt: now(),
        updatedAt: now(),
      }),
      setDoc(doc(db, "users_public/contact"), {
        schemaVersion: 2,
        uid: "contact",
        displayName: "Contact",
        createdAt: now(),
        updatedAt: now(),
      }),
      setDoc(doc(db, "groups/group-a"), groupData()),
      setDoc(doc(db, "groups/group-a/members/owner"), {
        uid: "owner",
        role: "owner",
        status: "active",
        joinedAt: now(),
      }),
      setDoc(doc(db, "groups/group-a/members/member"), {
        uid: "member",
        role: "member",
        status: "active",
        joinedAt: now(),
      }),
      setDoc(doc(db, "groups/group-a/messages/existing-message"), {
        schemaVersion: 2,
        senderId: "member",
        senderName: "Member",
        space: "discussion",
        parts: [{ type: "text", content: "Existing" }],
        timestamp: now(),
        isEdited: false,
        isDeleted: false,
      }),
      setDoc(doc(db, "managed_assets/asset-message-a"), {
        schemaVersion: 1,
        assetId: "asset-message-a",
        bucket: "demo-braid-rules.appspot.com",
        storagePath:
          "groups/group-a/messages/message-media/attachment.jpg",
        ownerUid: "member",
        entityType: "message",
        entityId: "message-media",
        groupId: "group-a",
        mimeType: "image/jpeg",
        sizeBytes: 8,
        status: "pending",
        createdAt: now(),
      }),
      setDoc(doc(db, "moderation_operators/operator"), {
        uid: "operator",
        role: "moderator",
        status: "active",
        assignedAt: now(),
      }),
      setDoc(doc(db, "moderation_audit/action-a"), {
        schemaVersion: 1,
        actionId: "action-a",
        operatorUid: "operator",
        action: "remove_content",
        reportId: "report-a",
        createdAt: now(),
      }),
      setDoc(doc(db, "insights/insight-a"), insightData()),
      setDoc(doc(db, "users/author/connections/contact"), {
        status: "accepted",
        otherUid: "contact",
        acceptedAt: now(),
      }),
      setDoc(doc(db, "users/contact/connections/author"), {
        status: "accepted",
        otherUid: "author",
        acceptedAt: now(),
      }),
    ]);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: RULES },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

describe("private and public user boundaries", () => {
  test("anonymous callers cannot read profiles", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "users_public/owner")));
    await assertFails(getDoc(doc(db, "users_private/owner")));
  });

  test("authenticated callers can get a known public profile but cannot enumerate", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    await assertSucceeds(getDoc(doc(db, "users_public/owner")));
    await assertFails(getDocs(collection(db, "users_public")));
  });

  test("private and legacy profiles are owner-only", async () => {
    const ownerDb = testEnv.authenticatedContext("owner").firestore();
    const otherDb = testEnv.authenticatedContext("member").firestore();

    await assertSucceeds(getDoc(doc(ownerDb, "users_private/owner")));
    await assertSucceeds(getDoc(doc(ownerDb, "users/owner")));
    await assertFails(getDoc(doc(otherDb, "users_private/owner")));
    await assertFails(getDoc(doc(otherDb, "users/owner")));
  });

  test("clients cannot mark an unverified phone as verified", async () => {
    const db = testEnv.authenticatedContext("owner").firestore();
    await assertFails(
      updateDoc(doc(db, "users_private/owner"), {
        phoneVerified: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, "users_private/owner"), {
        connectionCount: 500,
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("device notification preferences", () => {
  test("owner can create and update a bounded private device record", async () => {
    const db = testEnv.authenticatedContext("owner").firestore();
    const deviceRef = doc(db, "users/owner/devices/device-a");
    await assertSucceeds(
      setDoc(deviceRef, {
        token: "t".repeat(40),
        platform: "android",
        notificationsEnabled: true,
        messageNotifications: false,
        insightNotifications: true,
        previewContent: false,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(deviceRef, {
        previewContent: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(deviceRef, {
        messageNotifications: "yes",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(deviceRef, {
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("group ownership and membership integrity", () => {
  test("members can read their group and nonmembers cannot", async () => {
    const memberDb = testEnv.authenticatedContext("member").firestore();
    const outsiderDb = testEnv.authenticatedContext("outsider").firestore();

    await assertSucceeds(getDoc(doc(memberDb, "groups/group-a")));
    await assertFails(getDoc(doc(outsiderDb, "groups/group-a")));
  });

  test("member-scoped group query succeeds and unscoped enumeration fails", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    const ownGroups = query(
      collection(db, "groups"),
      where("members", "array-contains", "member"),
    );

    await assertSucceeds(getDocs(ownGroups));
    await assertFails(getDocs(collection(db, "groups")));
  });

  test("new group creation is callable-only", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    const valid = {
      schemaVersion: 2,
      ownerId: "alice",
      name: "New Study",
      members: ["alice"],
      readingProgress: { alice: 0 },
      userCompletedChapters: { alice: [] },
      unreadCounts: { alice: 0 },
      pinnedScripture: "",
      description: "",
      createdAt: serverTimestamp(),
      groupType: "Bible",
      lifecycle: "draft",
      extensionCount: 0,
    };

    await assertFails(setDoc(doc(db, "groups/valid"), valid));
    await assertFails(
      setDoc(doc(db, "groups/spoofed"), {
        ...valid,
        ownerId: "victim",
      }),
    );
  });

  test("ordinary members cannot add themselves or mutate roles", async () => {
    const db = testEnv.authenticatedContext("member").firestore();

    await assertFails(
      updateDoc(doc(db, "groups/group-a"), {
        members: ["owner", "member", "outsider"],
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/members/outsider"), {
        uid: "outsider",
        role: "owner",
      }),
    );
  });

  test("owner metadata and membership mutations are callable-only", async () => {
    const db = testEnv.authenticatedContext("owner").firestore();

    await assertFails(
      updateDoc(doc(db, "groups/group-a"), {
        name: "Renamed Study",
      }),
    );
    await assertFails(
      updateDoc(doc(db, "groups/group-a"), {
        members: ["owner"],
      }),
    );
  });

  test("members can change only their own progress fields", async () => {
    const db = testEnv.authenticatedContext("member").firestore();

    await assertSucceeds(
      updateDoc(doc(db, "groups/group-a"), {
        "readingProgress.member": 0.5,
      }),
    );
    await assertFails(
      updateDoc(doc(db, "groups/group-a"), {
        "readingProgress.owner": 1,
      }),
    );
  });
});

describe("messages", () => {
  test("message creation is callable-only for every payload shape", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    const validMessage = {
      schemaVersion: 2,
      clientMessageId: "client-1",
      space: "reflection",
      senderId: "member",
      senderName: "Member",
      senderPhotoUrl: "https://example.com/member.jpg",
      parts: [{ type: "text", content: "Hello" }],
      clientCreatedAt: now(),
      timestamp: serverTimestamp(),
      isEdited: false,
      isDeleted: false,
    };

    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/message-a"), validMessage),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/spoofed"), {
        ...validMessage,
        senderId: "owner",
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/spoofed-name"), {
        ...validMessage,
        senderName: "Owner",
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/spoofed-photo"), {
        ...validMessage,
        senderPhotoUrl: "https://example.com/owner.jpg",
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/oversized"), {
        ...validMessage,
        parts: [{ type: "text", content: "x".repeat(8001) }],
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/invalid-space"), {
        ...validMessage,
        space: "announcements",
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/inline-media"), {
        ...validMessage,
        parts: [{
          type: "voice",
          content: "https://tracker.example/audio.m4a",
          durationSeconds: 10,
        }],
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/message-media"), {
        ...validMessage,
        parts: [{
          type: "image",
          content: "groups/group-a/messages/message-media/attachment.jpg",
          assetId: "asset-message-a",
          sizeBytes: 8,
        }],
      }),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/wrong-media-owner"), {
        ...validMessage,
        parts: [{
          type: "image",
          content: "groups/group-a/messages/message-media/attachment.jpg",
          assetId: "asset-message-a",
          sizeBytes: 8,
        }],
      }),
    );
  });

  test("scheduled and completed studies are read-only", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await Promise.all([
        setDoc(
          doc(db, "groups/scheduled-group"),
          groupData({ lifecycle: "scheduled" }),
        ),
        setDoc(
          doc(db, "groups/completed-group"),
          groupData({ lifecycle: "completed" }),
        ),
      ]);
    });
    const db = testEnv.authenticatedContext("member").firestore();
    const message = {
      schemaVersion: 2,
      senderId: "member",
      senderName: "Member",
      space: "discussion",
      parts: [{ type: "text", content: "Too early or too late" }],
      timestamp: serverTimestamp(),
    };
    await assertFails(
      setDoc(doc(db, "groups/scheduled-group/messages/message-a"), message),
    );
    await assertFails(
      setDoc(doc(db, "groups/completed-group/messages/message-a"), message),
    );
  });

  test("a four-part text message cannot bypass the callable", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/four-part-text"), {
        schemaVersion: 2,
        senderId: "member",
        senderName: "Member",
        space: "discussion",
        parts: [
          { type: "text", content: "First" },
          { type: "text", content: "Second" },
          { type: "text", content: "Third" },
          { type: "text", content: "Fourth" },
        ],
        timestamp: serverTimestamp(),
      }),
    );
  });

  test("message edits and tombstones are callable-only", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    await assertFails(
      updateDoc(doc(db, "groups/group-a/messages/existing-message"), {
        parts: [{ type: "text", content: "Edited" }],
        isEdited: true,
        editedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, "groups/group-a/messages/existing-message"), {
        parts: [],
        isDeleted: true,
        deletedAt: serverTimestamp(),
      }),
    );
  });

  test("nonmembers cannot read or send group messages", async () => {
    const db = testEnv.authenticatedContext("outsider").firestore();
    await assertFails(
      getDocs(collection(db, "groups/group-a/messages")),
    );
    await assertFails(
      setDoc(doc(db, "groups/group-a/messages/message-b"), {
        schemaVersion: 2,
        senderId: "outsider",
        senderName: "Outsider",
        parts: [{ type: "text", content: "Hello" }],
        timestamp: serverTimestamp(),
      }),
    );
  });
});

describe("contacts-only insights and safety controls", () => {
  test("Insight publication is callable-only", async () => {
    const db = testEnv.authenticatedContext("author").firestore();
    await assertFails(
      setDoc(doc(db, "insights/client-created"), insightData()),
    );
  });

  test("accepted contact can read while unrelated account cannot", async () => {
    const contactDb = testEnv.authenticatedContext("contact").firestore();
    const strangerDb = testEnv.authenticatedContext("stranger").firestore();

    await assertSucceeds(getDoc(doc(contactDb, "insights/insight-a")));
    await assertFails(getDoc(doc(strangerDb, "insights/insight-a")));
    await assertFails(getDocs(collection(contactDb, "insights")));
  });

  test("blocking immediately removes contacts-only access", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/author/blocks/contact"), {
        blockedUid: "contact",
        createdAt: now(),
      });
    });

    const db = testEnv.authenticatedContext("contact").firestore();
    await assertFails(getDoc(doc(db, "insights/insight-a")));
  });

  test("nonauthor cannot edit or delete an Insight", async () => {
    const db = testEnv.authenticatedContext("contact").firestore();
    await assertFails(
      updateDoc(doc(db, "insights/insight-a"), {
        body: "Tampered",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test("comment creation is callable-only", async () => {
    const db = testEnv.authenticatedContext("contact").firestore();
    const validComment = {
      schemaVersion: 2,
      insightId: "insight-a",
      authorUid: "contact",
      authorName: "Contact",
      body: "Thank you for sharing.",
      createdAt: serverTimestamp(),
    };

    await assertFails(
      setDoc(
        doc(db, "insights/insight-a/comments/comment-a"),
        validComment,
      ),
    );
    await assertFails(
      setDoc(doc(db, "insights/insight-a/comments/spoofed"), {
        ...validComment,
        authorUid: "author",
      }),
    );
    await assertFails(
      setDoc(doc(db, "insights/insight-a/comments/spoofed-name"), {
        ...validComment,
        authorName: "Author",
      }),
    );
  });
});

describe("private state and reporting", () => {
  test("account deletion status is owner-readable and server-written", async () => {
    const ownerDb = testEnv.authenticatedContext("owner").firestore();
    const otherDb = testEnv.authenticatedContext("member").firestore();
    const ownerJob = doc(ownerDb, "account_deletion_jobs/owner");

    await assertSucceeds(getDoc(ownerJob));
    await assertFails(
      getDoc(doc(otherDb, "account_deletion_jobs/owner")),
    );
    await assertFails(updateDoc(ownerJob, { status: "complete" }));
  });

  test("group mute state is owner-only, bounded, and group-bound", async () => {
    const ownerDb = testEnv.authenticatedContext("owner").firestore();
    const otherDb = testEnv.authenticatedContext("member").firestore();
    const stateRef = doc(ownerDb, "users/owner/group_state/group-a");
    await assertSucceeds(
      setDoc(stateRef, {
        groupId: "group-a",
        mutedUntil: future(30),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(ownerDb, "users/owner/group_state/group-b"), {
        groupId: "group-a",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(ownerDb, "users/owner/group_state/too-long"), {
        groupId: "too-long",
        mutedUntil: future(400),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      getDoc(doc(otherDb, "users/owner/group_state/group-a")),
    );
  });

  test("saved Insight references are owner-only and immutable", async () => {
    const ownerDb = testEnv.authenticatedContext("owner").firestore();
    const otherDb = testEnv.authenticatedContext("member").firestore();

    await assertSucceeds(
      setDoc(doc(ownerDb, "users/owner/saved_insights/insight-a"), {
        insightId: "insight-a",
        savedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      getDoc(doc(otherDb, "users/owner/saved_insights/insight-a")),
    );

    await assertSucceeds(
      setDoc(doc(ownerDb, "users/owner/saved_insights/insight-b"), {
        schemaVersion: 2,
        snapshotSchemaVersion: 1,
        insightId: "insight-b",
        savedAt: serverTimestamp(),
        authorUid: "author",
        authorName: "Author",
        title: "A saved reflection",
        body: "A bounded saved snapshot.",
        themeId: "theme_0",
        audience: "contacts",
        status: "active",
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        expiresAt: future(72),
      }),
    );
    await assertFails(
      setDoc(doc(ownerDb, "users/owner/saved_insights/invalid"), {
        schemaVersion: 2,
        snapshotSchemaVersion: 1,
        insightId: "invalid",
        savedAt: serverTimestamp(),
        authorUid: "author",
        authorName: "Author",
        title: "Invalid snapshot",
        body: "x".repeat(12_001),
        themeId: "theme_0",
        audience: "contacts",
        status: "active",
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        expiresAt: future(72),
      }),
    );
  });

  test("reports are callable-only and cannot be edited by clients", async () => {
    const db = testEnv.authenticatedContext("member").firestore();
    const reportRef = doc(db, "reports/report-a");

    await assertFails(
      setDoc(reportRef, {
        schemaVersion: 2,
        reporterUid: "member",
        targetType: "message",
        targetId: "message-a",
        groupId: "group-a",
        reason: "harassment",
        status: "open",
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(reportRef, {
        status: "closed",
      }),
    );
    await assertFails(
      setDoc(doc(db, "reports/spoofed"), {
        schemaVersion: 2,
        reporterUid: "owner",
        targetType: "user",
        targetId: "victim",
        reason: "spam",
        status: "open",
        createdAt: serverTimestamp(),
      }),
    );
  });

  test("only actively assigned operators can read moderation audit", async () => {
    const operatorDb = testEnv
      .authenticatedContext("operator", { moderationRole: "moderator" })
      .firestore();
    const staleClaimDb = testEnv
      .authenticatedContext("stale", { moderationRole: "moderator" })
      .firestore();
    const memberDb = testEnv.authenticatedContext("member").firestore();

    await assertSucceeds(
      getDoc(doc(operatorDb, "moderation_audit/action-a")),
    );
    await assertFails(
      getDoc(doc(staleClaimDb, "moderation_audit/action-a")),
    );
    await assertFails(
      getDoc(doc(memberDb, "moderation_audit/action-a")),
    );
  });
});
