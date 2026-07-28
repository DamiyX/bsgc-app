const { after, before, beforeEach, describe, test } = require("node:test");
const path = require("node:path");
const fs = require("node:fs");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { Timestamp, doc, setDoc } = require("firebase/firestore");
const {
  getBytes,
  ref,
  uploadBytes,
} = require("firebase/storage");

const PROJECT_ID = "demo-braid-rules";
const ROOT = path.resolve(__dirname, "../../..");
const FIRESTORE_RULES = fs.readFileSync(
  path.join(ROOT, "firestore.rules"),
  "utf8",
);
const STORAGE_RULES = fs.readFileSync(
  path.join(ROOT, "storage.rules"),
  "utf8",
);

let testEnv;

function bytes(length = 8) {
  return new Uint8Array(length);
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "groups/group-a"), {
      schemaVersion: 2,
      ownerId: "owner",
      name: "Morning Study",
      members: ["owner", "member"],
      description: "",
      createdAt: Timestamp.now(),
      groupType: "Bible",
      lifecycle: "active",
      extensionCount: 0,
    });

    await uploadBytes(
      ref(context.storage(), "groups/group-a/covers/existing.jpg"),
      bytes(),
      {
        contentType: "image/jpeg",
        customMetadata: {
          ownerId: "owner",
          groupId: "group-a",
        },
      },
    );
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: FIRESTORE_RULES },
    storage: { rules: STORAGE_RULES },
  });
});

beforeEach(async () => {
  await Promise.all([
    testEnv.clearFirestore(),
    testEnv.clearStorage(),
  ]);
  await seed();
});

after(async () => {
  await testEnv.cleanup();
});

describe("profile media", () => {
  test("profile owner can upload a bounded image", async () => {
    const storage = testEnv.authenticatedContext("owner").storage();
    await assertSucceeds(
      uploadBytes(ref(storage, "users/owner/profile/avatar.jpg"), bytes(), {
        contentType: "image/jpeg",
        customMetadata: { ownerId: "owner" },
      }),
    );
  });

  test("another user and invalid content types are denied", async () => {
    const memberStorage = testEnv.authenticatedContext("member").storage();
    const ownerStorage = testEnv.authenticatedContext("owner").storage();

    await assertFails(
      uploadBytes(
        ref(memberStorage, "users/owner/profile/avatar.jpg"),
        bytes(),
        {
          contentType: "image/jpeg",
          customMetadata: { ownerId: "member" },
        },
      ),
    );
    await assertFails(
      uploadBytes(
        ref(ownerStorage, "users/owner/profile/avatar.exe"),
        bytes(),
        {
          contentType: "application/octet-stream",
          customMetadata: { ownerId: "owner" },
        },
      ),
    );
  });
});

describe("group media", () => {
  test("only the owner can upload a cover and only members can read it", async () => {
    const ownerStorage = testEnv.authenticatedContext("owner").storage();
    const memberStorage = testEnv.authenticatedContext("member").storage();
    const outsiderStorage = testEnv.authenticatedContext("outsider").storage();

    await assertSucceeds(
      uploadBytes(
        ref(ownerStorage, "groups/group-a/covers/new.jpg"),
        bytes(),
        {
          contentType: "image/jpeg",
          customMetadata: {
            ownerId: "owner",
            groupId: "group-a",
          },
        },
      ),
    );
    await assertFails(
      uploadBytes(
        ref(memberStorage, "groups/group-a/covers/member.jpg"),
        bytes(),
        {
          contentType: "image/jpeg",
          customMetadata: {
            ownerId: "member",
            groupId: "group-a",
          },
        },
      ),
    );
    await assertSucceeds(
      getBytes(
        ref(memberStorage, "groups/group-a/covers/existing.jpg"),
      ),
    );
    await assertFails(
      getBytes(
        ref(outsiderStorage, "groups/group-a/covers/existing.jpg"),
      ),
    );
  });

  test("message uploads require membership, allowed type, and matching metadata", async () => {
    const memberStorage = testEnv.authenticatedContext("member").storage();
    const outsiderStorage = testEnv.authenticatedContext("outsider").storage();
    const path = "groups/group-a/messages/message-a/attachment.jpg";
    const metadata = {
      contentType: "image/jpeg",
      customMetadata: {
        ownerId: "member",
        groupId: "group-a",
        messageId: "message-a",
      },
    };

    await assertSucceeds(
      uploadBytes(ref(memberStorage, path), bytes(), metadata),
    );
    await assertFails(
      uploadBytes(
        ref(memberStorage, "groups/group-a/messages/message-b/file.pdf"),
        bytes(),
        {
          contentType: "application/pdf",
          customMetadata: {
            ownerId: "member",
            groupId: "group-a",
            messageId: "message-b",
          },
        },
      ),
    );
    await assertFails(
      uploadBytes(
        ref(
          outsiderStorage,
          "groups/group-a/messages/message-c/attachment.jpg",
        ),
        bytes(),
        {
          contentType: "image/jpeg",
          customMetadata: {
            ownerId: "outsider",
            groupId: "group-a",
            messageId: "message-c",
          },
        },
      ),
    );
  });
});
