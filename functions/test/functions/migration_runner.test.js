"use strict";

const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  rollbackMigration,
  runMigration,
} = require("../../lib/migration_runner");

function fakeAdapter(seed, {
  failAfterCommits = null,
  throwAfterAtomicCommitAt = null,
} = {}) {
  const documents = structuredClone(seed);
  const runs = new Map();
  const beforeImages = new Map();
  let commits = 0;
  let activeCommits = 0;
  let maxActiveCommits = 0;
  let lease = null;
  return {
    documents,
    runs,
    beforeImages,
    stats: () => ({ commits, maxActiveCommits }),
    async loadRun(runId) {
      return runs.get(runId) ?? null;
    },
    async saveRun(runId, state) {
      runs.set(runId, structuredClone(state));
    },
    async acquireLease(runId, owner, expiresAtMillis) {
      if (lease && lease.owner !== owner && lease.expiresAtMillis > Date.now()) {
        throw new Error("migration run lease is already held");
      }
      lease = { runId, owner, expiresAtMillis };
    },
    async renewLease(runId, owner, expiresAtMillis) {
      if (!lease || lease.owner !== owner || lease.runId !== runId) {
        throw new Error("migration run lease was lost");
      }
      lease.expiresAtMillis = expiresAtMillis;
    },
    async releaseLease(runId, owner) {
      if (lease?.runId === runId && lease.owner === owner) lease = null;
    },
    async fetchPage(phase, afterId, limit) {
      return Object.entries(documents)
        .filter(([path]) => path.startsWith(`${phase}/`))
        .map(([path, data]) => ({
          id: path.slice(phase.length + 1),
          path,
          data: structuredClone(data),
        }))
        .filter((document) => !afterId || document.id > afterId)
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
      if (failAfterCommits !== null && commits === failAfterCommits) {
        failAfterCommits = null;
        throw new Error("injected interruption");
      }
      activeCommits += 1;
      maxActiveCommits = Math.max(maxActiveCommits, activeCommits);
      await Promise.resolve();
      for (const operation of operations) {
        if (operation.delete) delete documents[operation.path];
        else documents[operation.path] = structuredClone(operation.data);
      }
      commits += 1;
      activeCommits -= 1;
    },
    async commitWithCheckpoint(runId, operations, state) {
      await this.commit(operations);
      runs.set(runId, structuredClone(state));
      if (throwAfterAtomicCommitAt !== null
        && commits === throwAfterAtomicCommitAt) {
        throwAfterAtomicCommitAt = null;
        throw new Error("ambiguous atomic commit response");
      }
    },
    async readBeforeImages(runId) {
      return [...(beforeImages.get(runId) ?? new Map()).entries()].map(
        ([path, data]) => ({ path, existed: data !== null, data }),
      );
    },
  };
}

const phases = [{
  name: "legacy",
  transform(document) {
    return {
      operations: [{
        path: document.path,
        data: { schemaVersion: 2, value: document.data.value },
      }],
    };
  },
}];

describe("resumable migration runner", () => {
  test("uses deterministic cursors, bounded batches, and resumes safely", async () => {
    const adapter = fakeAdapter({
      "legacy/c": { value: "C" },
      "legacy/a": { value: "A" },
      "legacy/b": { value: "B" },
    }, { failAfterCommits: 1 });

    await assert.rejects(
      runMigration({
        adapter,
        phases,
        runId: "run-resume",
        apply: true,
        pageSize: 2,
        batchSize: 1,
        concurrency: 2,
        nowMillis: 1000,
      }),
      /injected interruption/,
    );
    assert.equal(adapter.runs.get("run-resume").cursor, "a");

    const summary = await runMigration({
      adapter,
      phases,
      runId: "run-resume",
      apply: true,
      pageSize: 2,
      batchSize: 1,
      concurrency: 2,
      nowMillis: 999999,
    });

    assert.equal(summary.status, "complete");
    assert.deepEqual(
      Object.keys(adapter.documents).sort(),
      ["legacy/a", "legacy/b", "legacy/c"],
    );
    assert.equal(adapter.documents["legacy/c"].schemaVersion, 2);
    assert.equal(adapter.runs.get("run-resume").startedAtMillis, 1000);
    assert.ok(adapter.stats().commits >= 3);
    assert.ok(adapter.stats().maxActiveCommits <= 2);
  });

  test("dry-run summaries contain hashes and lengths, never source content", async () => {
    const adapter = fakeAdapter({
      "legacy/a": { value: "private prayer request" },
    });
    const summary = await runMigration({
      adapter,
      phases,
      runId: "run-dry",
      apply: false,
      pageSize: 10,
      batchSize: 5,
      concurrency: 1,
      nowMillis: 1000,
    });
    const serialized = JSON.stringify(summary);
    assert.doesNotMatch(serialized, /private prayer request/);
    assert.match(serialized, /sha256/);
    assert.equal(adapter.documents["legacy/a"].schemaVersion, undefined);
  });

  test("restores before-images and deletes documents created by migration", async () => {
    const adapter = fakeAdapter({ "legacy/a": { value: "before" } });
    const creatingPhase = [{
      name: "legacy",
      transform(document) {
        return {
          operations: [
            { path: document.path, data: { value: "after" } },
            { path: "canonical/new", data: { value: "created" } },
          ],
        };
      },
    }];
    await runMigration({
      adapter,
      phases: creatingPhase,
      runId: "run-rollback",
      apply: true,
      pageSize: 5,
      batchSize: 2,
      concurrency: 1,
      nowMillis: 1000,
    });
    assert.equal(adapter.documents["legacy/a"].value, "after");
    assert.equal(adapter.documents["canonical/new"].value, "created");

    const result = await rollbackMigration({
      adapter,
      runId: "run-rollback",
      batchSize: 1,
    });
    assert.equal(result.restored, 1);
    assert.equal(result.deleted, 1);
    assert.deepEqual(adapter.documents["legacy/a"], { value: "before" });
    assert.equal(adapter.documents["canonical/new"], undefined);
  });

  test("captures only the original before-image when a path is written twice", async () => {
    const adapter = fakeAdapter({
      "legacy/a": { value: "a" },
      "legacy/b": { value: "b" },
      "shared/target": { value: "original" },
    });
    await runMigration({
      adapter,
      phases: [{
        name: "legacy",
        transform(document) {
          return {
            operations: [{
              path: "shared/target",
              data: { value: document.data.value },
            }],
          };
        },
      }],
      runId: "run-first-image",
      apply: true,
      pageSize: 10,
      batchSize: 2,
      concurrency: 1,
      nowMillis: 1000,
    });
    assert.equal(adapter.documents["shared/target"].value, "b");
    await rollbackMigration({
      adapter,
      runId: "run-first-image",
      batchSize: 2,
    });
    assert.deepEqual(adapter.documents["shared/target"], { value: "original" });
  });

  test("rejects a concurrent owner of the same unexpired run lease", async () => {
    const adapter = fakeAdapter({ "legacy/a": { value: "a" } });
    await adapter.acquireLease(
      "run-leased",
      "first-owner",
      Date.now() + 60_000,
    );
    await assert.rejects(
      runMigration({
        adapter,
        phases,
        runId: "run-leased",
        apply: true,
        leaseOwner: "second-owner",
      }),
      /lease is already held/,
    );
  });

  test("an ambiguous atomic commit resumes without duplicate counts", async () => {
    const adapter = fakeAdapter({
      "legacy/a": { value: "A" },
    }, { throwAfterAtomicCommitAt: 1 });
    await assert.rejects(
      runMigration({
        adapter,
        phases,
        runId: "run-ambiguous",
        apply: true,
        pageSize: 1,
        batchSize: 1,
        concurrency: 1,
        nowMillis: 1000,
      }),
      /ambiguous atomic commit response/,
    );
    const summary = await runMigration({
      adapter,
      phases,
      runId: "run-ambiguous",
      apply: true,
      pageSize: 1,
      batchSize: 1,
      concurrency: 1,
      nowMillis: 2000,
    });
    assert.equal(summary.counts.read, 1);
    assert.equal(summary.counts.proposedWrites, 1);
    assert.equal(summary.counts.committedWrites, 1);
    assert.equal(adapter.stats().commits, 1);
  });
});
