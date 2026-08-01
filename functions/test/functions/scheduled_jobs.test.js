const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  buildWriteBatches,
  drainPagedJob,
} = require("../../lib/scheduled_jobs");
const { commitLifecycleUpdates } = require("../../lib/lifecycle");

describe("scheduled job safety", () => {
  test("accounts for multi-write items and never exceeds the safe cap", () => {
    const batches = buildWriteBatches([
      { id: "a", writeCount: 300 },
      { id: "b", writeCount: 149 },
      { id: "c", writeCount: 2 },
      { id: "d", writeCount: 448 },
    ]);
    assert.deepEqual(
      batches.map((batch) => batch.reduce(
        (total, item) => total + item.writeCount,
        0,
      )),
      [449, 450],
    );
  });

  test("rejects an item that cannot fit in one safe commit", () => {
    assert.throws(
      () => buildWriteBatches([{ id: "unsafe", writeCount: 451 }]),
      /exceeds/,
    );
  });

  test("pages until the time budget and reports backlog telemetry", async () => {
    const pages = [
      [{ id: "a", eligibleAtMillis: 1_000 }],
      [{ id: "b", eligibleAtMillis: 2_000 }],
      [{ id: "c", eligibleAtMillis: 3_000 }],
    ];
    let clock = 10_000;
    const processed = [];
    const metrics = await drainPagedJob({
      loadPage: async () => pages.shift() ?? [],
      processPage: async (items) => {
        processed.push(...items.map((item) => item.id));
        clock += 600;
        return { processed: items.length, errors: 0 };
      },
      inspectBacklog: async () => ({
        backlogCount: pages.flat().length,
        oldestEligibleAtMillis: pages.flat()[0]?.eligibleAtMillis ?? null,
      }),
      nowMillis: () => clock,
      timeBudgetMs: 1_000,
      pageSize: 1,
    });
    assert.deepEqual(processed, ["a", "b"]);
    assert.equal(metrics.processedCount, 2);
    assert.equal(metrics.errorCount, 0);
    assert.equal(metrics.backlogCount, 1);
    assert.equal(metrics.oldestAgeMs, 8_200);
    assert.equal(metrics.stoppedForTimeBudget, true);
  });

  test("mutation-derived paging eventually processes inserts around a cursor", async () => {
    const eligible = [
      { id: "b", eligibleAtMillis: 2 },
      { id: "c", eligibleAtMillis: 3 },
    ];
    const processed = [];
    await drainPagedJob({
      loadPage: async ({ limit }) =>
        eligible.slice().sort((a, b) => a.id.localeCompare(b.id)).slice(0, limit),
      processPage: async (items) => {
        processed.push(...items.map((item) => item.id));
        for (const item of items) {
          eligible.splice(eligible.findIndex((entry) => entry.id === item.id), 1);
        }
        if (items.some((item) => item.id === "b")) {
          eligible.push({ id: "a", eligibleAtMillis: 1 });
        }
        return { processed: items.length, errors: 0 };
      },
      inspectBacklog: async () => ({ backlogCount: eligible.length }),
      nowMillis: () => 10,
      timeBudgetMs: 100,
      pageSize: 1,
    });
    assert.deepEqual(processed, ["b", "a", "c"]);
    assert.equal(eligible.length, 0);
  });

  test("drains more than 1,000 lifecycle writes without an oversized commit", async () => {
    const eligible = Array.from({ length: 1_200 }, (_, index) => ({
      id: `group-${index.toString().padStart(4, "0")}`,
      ref: { id: `group-${index}` },
    }));
    const batchSizes = [];
    const firestore = {
      batch() {
        const updates = [];
        return {
          update(reference, values) {
            updates.push({ reference, values });
          },
          async commit() {
            if (updates.length > 450) throw new Error("oversized commit");
            batchSizes.push(updates.length);
          },
        };
      },
    };
    const metrics = await drainPagedJob({
      loadPage: async ({ limit }) => eligible.slice(0, limit),
      processPage: async (items) => {
        await commitLifecycleUpdates({
          firestore,
          scheduledDocuments: items,
          activeDocuments: [],
          now: { seconds: 1 },
          maxBatchWrites: 450,
        });
        eligible.splice(0, items.length);
        return { processed: items.length, errors: 0 };
      },
      inspectBacklog: async () => ({ backlogCount: eligible.length }),
      nowMillis: () => 1,
      timeBudgetMs: 10,
      pageSize: 450,
    });
    assert.equal(metrics.processedCount, 1_200);
    assert.equal(metrics.backlogCount, 0);
    assert.deepEqual(batchSizes, [450, 450, 300]);
  });
});
