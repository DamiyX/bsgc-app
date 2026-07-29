"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const {
  ACCOUNT_DELETION_PHASES,
  createAccountDeletionHandlers,
  processDeletionStep,
} = require("../../lib/account_deletion");

describe("durable account deletion phase machine", () => {
  it("keeps the same phase while another bounded page remains", async () => {
    let calls = 0;
    const result = await processDeletionStep({
      job: { phase: "messages", completedPages: 2 },
      handlers: {
        messages: async () => {
          calls++;
          return { done: false, processed: 100 };
        },
      },
    });

    assert.equal(calls, 1);
    assert.equal(result.phase, "messages");
    assert.equal(result.completedPages, 3);
    assert.equal(result.processedInLastPage, 100);
    assert.equal(result.complete, false);
  });

  it("persists the preflight cursor between bounded ownership pages",
    async () => {
      const result = await processDeletionStep({
        job: { phase: "preflight", completedPages: 0 },
        handlers: {
          preflight: async () => ({
            done: false,
            processed: 50,
            cursor: "group-050",
          }),
        },
      });

      assert.equal(result.phase, "preflight");
      assert.equal(result.cursor, "group-050");
      assert.equal(result.completedPages, 1);
    });

  it("advances exactly one phase after a page reports reconciliation", async () => {
    const result = await processDeletionStep({
      job: { phase: "comments", completedPages: 4 },
      handlers: {
        comments: async () => ({ done: true, processed: 0 }),
      },
    });

    assert.equal(result.phase, "reactions");
    assert.equal(result.completedPages, 4);
    assert.equal(result.complete, false);
  });

  it("marks complete only after the final verification phase", async () => {
    const finalPhase = ACCOUNT_DELETION_PHASES.at(-1);
    assert.equal(finalPhase, "verify");

    const result = await processDeletionStep({
      job: { phase: finalPhase, completedPages: 12 },
      handlers: {
        verify: async () => ({ done: true, processed: 0 }),
      },
    });

    assert.equal(result.phase, "complete");
    assert.equal(result.complete, true);
  });

  it("rejects unknown persisted phases instead of skipping cleanup", async () => {
    await assert.rejects(
      processDeletionStep({
        job: { phase: "profiles", completedPages: 0 },
        handlers: {},
      }),
      /Unknown account deletion phase/,
    );
  });

  it("does not disable auth when shared-group ownership blocks deletion",
    async () => {
      let authMutations = 0;
      const groupDocument = {
        data: () => ({ ownerId: "user-1", members: ["user-1", "user-2"] }),
      };
      const query = {
        where: () => query,
        orderBy: () => query,
        limit: () => query,
        startAfter: () => query,
        get: async () => ({
          docs: [groupDocument],
          size: 1,
          empty: false,
        }),
      };
      const handlers = createAccountDeletionHandlers({
        uid: "user-1",
        db: { collection: () => query },
        auth: {
          updateUser: async () => authMutations++,
          revokeRefreshTokens: async () => authMutations++,
        },
        bucket: {},
        FieldValue: {},
        FieldPath: { documentId: () => "__name__" },
        Timestamp: {},
        job: {},
      });

      await assert.rejects(handlers.preflight(), /Transfer ownership/);
      assert.equal(authMutations, 0);
    });

  it("keeps a message discoverable when media cleanup fails", async () => {
    let tombstoneWrites = 0;
    const message = {
      id: "message-1",
      data: () => ({ parts: [] }),
      ref: { parent: { parent: { id: "group-1" } } },
    };
    const query = {
      where: () => query,
      limit: () => query,
      get: async () => ({ docs: [message], size: 1, empty: false }),
    };
    const handlers = createAccountDeletionHandlers({
      uid: "user-1",
      db: {
        collectionGroup: () => query,
        batch: () => ({
          update: () => tombstoneWrites++,
          commit: async () => {},
        }),
      },
      auth: {},
      bucket: {
        deleteFiles: async () => {
          throw new Error("storage unavailable");
        },
      },
      FieldValue: { delete: () => null },
      Timestamp: { now: () => "now" },
    });

    await assert.rejects(handlers.messages(), /storage unavailable/);
    assert.equal(tombstoneWrites, 0);
  });

  it("re-enables auth if shared ownership races with the frozen job",
    async () => {
      const authUpdates = [];
      let deletionState;
      const group = {
        data: () => ({ ownerId: "user-1", members: ["user-1", "user-2"] }),
      };
      const query = {
        where: () => query,
        limit: () => query,
        get: async () => ({ docs: [group], size: 1, empty: false }),
      };
      const handlers = createAccountDeletionHandlers({
        uid: "user-1",
        db: {
          collection: () => query,
          doc: () => ({
            set: async (value) => {
              deletionState = value.deletionState;
            },
          }),
        },
        auth: {
          updateUser: async (_uid, value) => authUpdates.push(value),
        },
        bucket: {},
        FieldValue: {},
        Timestamp: { now: () => "now" },
      });

      await assert.rejects(handlers.memberships(), /Transfer ownership/);
      assert.deepEqual(authUpdates, [{ disabled: false }]);
      assert.equal(deletionState, "blocked");
    });
});
