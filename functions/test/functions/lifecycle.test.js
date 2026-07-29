const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  commitLifecycleUpdates,
} = require("../../lib/lifecycle");

function createDocument(id) {
  return { ref: { id } };
}

function createFirestoreRecorder() {
  const committedBatches = [];
  return {
    committedBatches,
    firestore: {
      batch() {
        const updates = [];
        return {
          update(reference, values) {
            updates.push({ reference, values });
          },
          async commit() {
            if (updates.length > 500) {
              throw new Error(`Firestore batch exceeded 500 writes: ${updates.length}`);
            }
            committedBatches.push(updates);
          },
        };
      },
    },
  };
}

describe("group lifecycle advancement", () => {
  test("commits 800 eligible groups in batches below Firestore's limit", async () => {
    const recorder = createFirestoreRecorder();
    const now = { seconds: 123 };
    const scheduledDocuments = Array.from(
      { length: 400 },
      (_, index) => createDocument(`scheduled-${index}`),
    );
    const activeDocuments = Array.from(
      { length: 400 },
      (_, index) => createDocument(`active-${index}`),
    );

    const result = await commitLifecycleUpdates({
      firestore: recorder.firestore,
      scheduledDocuments,
      activeDocuments,
      now,
    });

    assert.equal(result.activatedCount, 400);
    assert.equal(result.completedCount, 400);
    assert.equal(result.batchCount, 2);
    assert.deepEqual(
      recorder.committedBatches.map((updates) => updates.length),
      [450, 350],
    );
    assert.deepEqual(recorder.committedBatches[0][0].values, {
      lifecycle: "active",
      activatedAt: now,
    });
    assert.deepEqual(recorder.committedBatches[1][349].values, {
      lifecycle: "completed",
      completedAt: now,
    });
  });

  test("does not create an empty Firestore batch", async () => {
    const recorder = createFirestoreRecorder();

    const result = await commitLifecycleUpdates({
      firestore: recorder.firestore,
      scheduledDocuments: [],
      activeDocuments: [],
      now: { seconds: 123 },
    });

    assert.deepEqual(result, {
      activatedCount: 0,
      completedCount: 0,
      batchCount: 0,
    });
    assert.equal(recorder.committedBatches.length, 0);
  });
});
