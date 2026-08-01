const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  buildGroupCoverAssetRecord,
  buildMessageAssetRecord,
  collectMessageAssetReferences,
  deleteUnregisteredMessageAsset,
  isCanonicalMessageAssetPath,
  managedAssetIdForPath,
  nextManagedAssetStatus,
  reconcileManagedReferences,
} = require("../../lib/managed_media");

describe("managed message media contracts", () => {
  test("creates canonical group-cover metadata", () => {
    const storagePath = "groups/group-a/covers/cover.jpg";
    const assetId = managedAssetIdForPath(storagePath);
    assert.deepEqual(buildGroupCoverAssetRecord({
      name: storagePath,
      bucket: "bucket-a",
      size: "8",
      contentType: "image/jpeg",
      metadata: { assetId, ownerId: "owner", groupId: "group-a" },
      timeCreated: "2026-07-29T10:00:00.000Z",
    }), {
      schemaVersion: 1,
      assetId,
      bucket: "bucket-a",
      storagePath,
      ownerUid: "owner",
      entityType: "group_cover",
      entityId: "group-a",
      groupId: "group-a",
      mimeType: "image/jpeg",
      sizeBytes: 8,
      status: "pending",
      createdAt: new Date("2026-07-29T10:00:00.000Z"),
    });
  });

  test("creates canonical pending metadata from a validated object", () => {
    const storagePath =
      "groups/group-a/messages/message-a/attachment.jpg";
    const assetId = managedAssetIdForPath(storagePath);
    const record = buildMessageAssetRecord({
      name: storagePath,
      bucket: "bucket-a",
      size: "42",
      contentType: "image/jpeg",
      crc32c: "checksum",
      metadata: {
        assetId,
        ownerId: "member",
        groupId: "group-a",
        messageId: "message-a",
      },
      timeCreated: "2026-07-29T10:00:00.000Z",
    });

    assert.deepEqual(record, {
      schemaVersion: 1,
      assetId,
      bucket: "bucket-a",
      storagePath,
      ownerUid: "member",
      entityType: "message",
      entityId: "message-a",
      groupId: "group-a",
      mimeType: "image/jpeg",
      sizeBytes: 42,
      checksum: "checksum",
      status: "pending",
      createdAt: new Date("2026-07-29T10:00:00.000Z"),
    });
  });

  test("rejects forged metadata and unsupported media", () => {
    const base = {
      name: "groups/group-a/messages/message-a/attachment.jpg",
      bucket: "bucket-a",
      size: "42",
      contentType: "image/jpeg",
      metadata: {
        ownerId: "member",
        groupId: "group-a",
        messageId: "message-a",
      },
    };
    base.metadata.assetId = managedAssetIdForPath(base.name);

    assert.equal(buildMessageAssetRecord({
      ...base,
      metadata: { ...base.metadata, groupId: "group-b" },
    }), null);
    assert.equal(buildMessageAssetRecord({
      ...base,
      contentType: "text/html",
    }), null);
    assert.equal(buildMessageAssetRecord({
      ...base,
      metadata: { ...base.metadata, assetId: "forged" },
    }), null);
  });

  test("recognizes only canonical message paths for orphan cleanup", () => {
    assert.equal(
      isCanonicalMessageAssetPath(
        "groups/group-a/messages/message-a/attachment.jpg",
      ),
      true,
    );
    assert.equal(
      isCanonicalMessageAssetPath("groups/group-a/covers/attachment.jpg"),
      false,
    );
  });

  test("deletes invalid canonical message objects but ignores other paths", async () => {
    const deleted = [];
    const storage = {
      bucket: (bucketName) => ({
        file: (storagePath) => ({
          delete: async (options) => {
            deleted.push({ bucketName, storagePath, options });
          },
        }),
      }),
    };

    assert.equal(await deleteUnregisteredMessageAsset({
      storage,
      object: {
        bucket: "bucket-a",
        name: "groups/group-a/messages/message-a/attachment.jpg",
      },
    }), true);
    assert.equal(await deleteUnregisteredMessageAsset({
      storage,
      object: {
        bucket: "bucket-a",
        name: "groups/group-a/covers/cover.jpg",
      },
    }), false);
    assert.deepEqual(deleted, [{
      bucketName: "bucket-a",
      storagePath: "groups/group-a/messages/message-a/attachment.jpg",
      options: { ignoreNotFound: true },
    }]);
  });

  test("collects only canonical managed references, never HTTPS URLs", () => {
    const imagePath = "groups/group-a/messages/message-a/image.jpg";
    const refs = collectMessageAssetReferences({
      senderId: "member",
      parts: [
        { type: "text", content: "https://example.com/link" },
        {
          type: "image",
          content: imagePath,
          assetId: managedAssetIdForPath(imagePath),
        },
        {
          type: "voice",
          content: "https://tracker.example/voice.m4a",
          assetId: "forged",
        },
      ],
    }, { groupId: "group-a", messageId: "message-a" });
    assert.deepEqual([...refs.entries()], [[
      managedAssetIdForPath(imagePath),
      {
        assetId: managedAssetIdForPath(imagePath),
        storagePath: imagePath,
        ownerUid: "member",
        mediaType: "image",
      },
    ]]);
  });

  test("rejects cross-group, cross-message, and forged asset references", () => {
    const references = [
      "groups/group-b/messages/message-a/image.jpg",
      "groups/group-a/messages/message-b/image.jpg",
      "groups/group-a/messages/message-a/image.jpg",
    ];
    const refs = collectMessageAssetReferences({
      senderId: "member",
      parts: references.map((content, index) => ({
        type: "image",
        content,
        assetId: index === 2
          ? "forged-id"
          : managedAssetIdForPath(content),
      })),
    }, { groupId: "group-a", messageId: "message-a" });
    assert.equal(refs.size, 0);
  });

  test("lifecycle transitions are monotonic and idempotent", () => {
    assert.equal(nextManagedAssetStatus("pending", "commit"), "committed");
    assert.equal(nextManagedAssetStatus("committed", "commit"), "committed");
    assert.equal(
      nextManagedAssetStatus("committed", "queueDeletion"),
      "delete_pending",
    );
    assert.equal(
      nextManagedAssetStatus("delete_pending", "queueDeletion"),
      "delete_pending",
    );
    assert.equal(nextManagedAssetStatus("delete_pending", "deleted"), "deleted");
    assert.equal(nextManagedAssetStatus("deleted", "commit"), "deleted");
  });

  test("preserves delete_pending metadata when object deletion fails",
    async () => {
      const state = {
        assetId: "asset-a",
        storagePath: "groups/group-a/messages/message-a/image.jpg",
        ownerUid: "member",
        entityType: "message",
        entityId: "message-a",
        groupId: "group-a",
        bucket: "bucket-a",
        status: "committed",
      };
      const assetRef = {
        update: async (values) => Object.assign(state, values),
      };
      const firestore = {
        doc: () => assetRef,
        runTransaction: async (operation) => operation({
          get: async () => ({ exists: true, data: () => ({ ...state }) }),
          update: (_reference, values) => Object.assign(state, values),
        }),
      };
      const storage = {
        bucket: () => ({
          file: () => ({
            delete: async () => {
              throw new Error("storage unavailable");
            },
          }),
        }),
      };
      const before = new Map([[
        "asset-a",
        {
          assetId: "asset-a",
          storagePath: state.storagePath,
          ownerUid: "member",
        },
      ]]);

      await assert.rejects(
        reconcileManagedReferences({
          firestore,
          storage,
          beforeReferences: before,
          afterReferences: new Map(),
          expectedEntityType: "message",
          expectedEntityId: "message-a",
          expectedGroupId: "group-a",
          now: "now",
        }),
        /storage unavailable/,
      );
      assert.equal(state.status, "delete_pending");
      assert.equal(state.deletedAt, undefined);
    });

  test("marks an object deleted only after idempotent storage removal",
    async () => {
      const state = {
        assetId: "asset-a",
        storagePath: "groups/group-a/messages/message-a/image.jpg",
        ownerUid: "member",
        entityType: "message",
        entityId: "message-a",
        groupId: "group-a",
        bucket: "bucket-a",
        status: "delete_pending",
      };
      let deleteCalls = 0;
      const assetRef = {
        update: async (values) => Object.assign(state, values),
      };
      const firestore = {
        doc: () => assetRef,
        runTransaction: async (operation) => operation({
          get: async () => ({ exists: true, data: () => ({ ...state }) }),
          update: (_reference, values) => Object.assign(state, values),
        }),
      };
      const storage = {
        bucket: () => ({
          file: () => ({
            delete: async ({ ignoreNotFound }) => {
              assert.equal(ignoreNotFound, true);
              deleteCalls++;
            },
          }),
        }),
      };

      await reconcileManagedReferences({
        firestore,
        storage,
        beforeReferences: new Map([[
          "asset-a",
          {
            assetId: "asset-a",
            storagePath: state.storagePath,
            ownerUid: "member",
          },
        ]]),
        afterReferences: new Map(),
        expectedEntityType: "message",
        expectedEntityId: "message-a",
        expectedGroupId: "group-a",
        now: "now",
      });

      assert.equal(deleteCalls, 1);
      assert.equal(state.status, "deleted");
      assert.equal(state.deletedAt, "now");
    });
});
