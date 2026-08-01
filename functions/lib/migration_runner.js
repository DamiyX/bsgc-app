"use strict";

const crypto = require("node:crypto");

function assertBounds({ pageSize, batchSize, concurrency }) {
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new RangeError("pageSize must be between 1 and 500");
  }
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 400) {
    throw new RangeError("batchSize must be between 1 and 400");
  }
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 16) {
    throw new RangeError("concurrency must be between 1 and 16");
  }
}

async function mapBounded(values, concurrency, callback) {
  const results = new Array(values.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await callback(values[index], index);
    }
  }
  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, values.length) },
      () => worker(),
    ),
  );
  return results;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function safeOperationSample(operation) {
  const serialized = operation.delete ? "" : JSON.stringify(operation.data);
  return {
    path: { algorithm: "sha256", digest: sha256(operation.path) },
    action: operation.delete ? "delete" : "replace",
    serializedLength: Buffer.byteLength(serialized, "utf8"),
    fieldCount: operation.data && typeof operation.data === "object"
      ? Object.keys(operation.data).length
      : 0,
  };
}

function safeIssue(issue) {
  const document = typeof issue?.document === "string"
    ? issue.document
    : "unknown";
  return {
    document: { algorithm: "sha256", digest: sha256(document) },
    code: typeof issue?.code === "string" ? issue.code : "migration-issue",
    fields: Array.isArray(issue?.fields)
      ? issue.fields.filter((field) => typeof field === "string").slice(0, 20)
      : [],
  };
}

function initialState(runId, phases, apply, nowMillis) {
  return {
    schemaVersion: 2,
    runId,
    mode: apply ? "apply" : "dry-run",
    status: "running",
    phaseIndex: 0,
    phase: phases[0]?.name ?? null,
    cursor: null,
    pending: null,
    startedAtMillis: nowMillis,
    updatedAtMillis: nowMillis,
    counts: {
      read: 0,
      proposedWrites: 0,
      committedWrites: 0,
      skipped: 0,
      issues: 0,
    },
    issues: [],
    samples: [],
  };
}

async function runMigration({
  adapter,
  phases,
  runId,
  apply = false,
  pageSize = 100,
  batchSize = 200,
  concurrency = 4,
  nowMillis = Date.now(),
  leaseNowMillis = Date.now,
  leaseOwner = crypto.randomUUID(),
  leaseDurationMillis = 5 * 60_000,
}) {
  assertBounds({ pageSize, batchSize, concurrency });
  if (!runId || typeof runId !== "string") {
    throw new TypeError("runId is required");
  }
  if (!Array.isArray(phases) || phases.length === 0) {
    throw new TypeError("at least one migration phase is required");
  }
  if (typeof leaseNowMillis !== "function") {
    throw new TypeError("leaseNowMillis must be a function");
  }

  const leaseExpiryMillis = () => leaseNowMillis() + leaseDurationMillis;

  if (typeof adapter.acquireLease === "function") {
    await adapter.acquireLease(
      runId,
      leaseOwner,
      leaseExpiryMillis(),
    );
  }
  let state = await adapter.loadRun(runId);
  if (!state?.runId) {
    state = initialState(runId, phases, apply, nowMillis);
    await adapter.saveRun(runId, state);
  } else {
    if (state.mode !== (apply ? "apply" : "dry-run")) {
      if (typeof adapter.releaseLease === "function") {
        await adapter.releaseLease(runId, leaseOwner);
      }
      throw new Error(`run ${runId} was created in ${state.mode} mode`);
    }
    if (state.status === "complete") {
      if (typeof adapter.releaseLease === "function") {
        await adapter.releaseLease(runId, leaseOwner);
      }
      return state;
    }
    state.status = "running";
  }

  try {
    for (
      let phaseIndex = state.phaseIndex;
      phaseIndex < phases.length;
      phaseIndex += 1
    ) {
      const phase = phases[phaseIndex];
      state.phaseIndex = phaseIndex;
      state.phase = phase.name;
      let cursor = state.cursor;
      while (true) {
        if (typeof adapter.renewLease === "function") {
          await adapter.renewLease(
            runId,
            leaseOwner,
            leaseExpiryMillis(),
          );
        }
        const page = await adapter.fetchPage(phase.name, cursor, pageSize);
        if (page.length === 0) break;
        const transformed = await mapBounded(
          page,
          concurrency,
          (document) => phase.transform(document, {
            runId,
            startedAtMillis: state.startedAtMillis,
          }),
        );
        for (let index = 0; index < page.length; index += 1) {
          const document = page[index];
          const result = transformed[index] ?? {};
          const operations = Array.isArray(result.operations)
            ? result.operations
            : [];
          const issues = Array.isArray(result.issues) ? result.issues : [];
          const resumingDocument = state.pending?.documentId === document.id;
          if (!resumingDocument) {
            state.counts.read += 1;
            state.counts.proposedWrites += operations.length;
            state.counts.issues += issues.length;
            if (operations.length === 0) state.counts.skipped += 1;
            state.issues.push(...issues.map(safeIssue).slice(
              0,
              Math.max(0, 100 - state.issues.length),
            ));
            for (const operation of operations) {
              if (state.samples.length < 25) {
                state.samples.push(safeOperationSample(operation));
              }
            }
          }
          if (apply) {
            if (typeof adapter.commitWithCheckpoint !== "function") {
              throw new Error(
                "Apply mode requires atomic commitWithCheckpoint support",
              );
            }
            const startOffset = resumingDocument
              ? state.pending.nextOperationOffset
              : 0;
            for (
              let operationIndex = startOffset;
              operationIndex < operations.length;
              operationIndex += batchSize
            ) {
              const batch = operations.slice(
                operationIndex,
                operationIndex + batchSize,
              );
              await adapter.captureBeforeImages(runId, batch);
              const nextOffset = operationIndex + batch.length;
              const nextState = structuredClone(state);
              nextState.counts.committedWrites += batch.length;
              nextState.updatedAtMillis = nowMillis;
              if (nextOffset < operations.length) {
                nextState.pending = {
                  documentId: document.id,
                  nextOperationOffset: nextOffset,
                };
              } else {
                nextState.pending = null;
                nextState.cursor = document.id;
              }
              await adapter.commitWithCheckpoint(runId, batch, nextState);
              state = nextState;
            }
          }
          cursor = document.id;
          state.cursor = cursor;
          state.pending = null;
          state.updatedAtMillis = nowMillis;
          if (!apply || operations.length === 0) {
            await adapter.saveRun(runId, state);
          }
          if (typeof adapter.renewLease === "function") {
            await adapter.renewLease(
              runId,
              leaseOwner,
              leaseExpiryMillis(),
            );
          }
        }
        if (page.length < pageSize) break;
      }
      state.cursor = null;
      state.phaseIndex = phaseIndex + 1;
      state.phase = phases[phaseIndex + 1]?.name ?? null;
      state.updatedAtMillis = nowMillis;
      await adapter.saveRun(runId, state);
    }
    state.status = "complete";
    state.completedAtMillis = nowMillis;
    state.updatedAtMillis = nowMillis;
    await adapter.saveRun(runId, state);
    return state;
  } catch (error) {
    state.status = "interrupted";
    state.updatedAtMillis = nowMillis;
    state.lastError = {
      name: error?.name ?? "Error",
      messageHash: sha256(String(error?.message ?? error)),
    };
    // In apply mode an ambiguous network failure may mean the atomic
    // data+checkpoint batch committed. Never overwrite that durable state
    // with the caller's possibly stale in-memory checkpoint.
    if (!apply) await adapter.saveRun(runId, state);
    throw error;
  } finally {
    if (typeof adapter.releaseLease === "function") {
      await adapter.releaseLease(runId, leaseOwner);
    }
  }
}

async function rollbackMigration({ adapter, runId, batchSize = 200 }) {
  assertBounds({ pageSize: 1, batchSize, concurrency: 1 });
  const beforeImages = await adapter.readBeforeImages(runId);
  const operations = beforeImages.map((image) => image.existed
    ? { path: image.path, data: image.data }
    : { path: image.path, delete: true });
  for (let index = 0; index < operations.length; index += batchSize) {
    await adapter.commit(operations.slice(index, index + batchSize));
  }
  return {
    runId,
    restored: beforeImages.filter((image) => image.existed).length,
    deleted: beforeImages.filter((image) => !image.existed).length,
  };
}

module.exports = {
  mapBounded,
  rollbackMigration,
  runMigration,
  safeIssue,
  safeOperationSample,
};
