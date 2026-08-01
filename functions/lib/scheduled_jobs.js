"use strict";

const SAFE_COMMIT_WRITE_LIMIT = 450;

function buildWriteBatches(
  items,
  { maxWrites = SAFE_COMMIT_WRITE_LIMIT } = {},
) {
  if (!Number.isInteger(maxWrites) || maxWrites < 1 || maxWrites > 500) {
    throw new RangeError("maxWrites must be between 1 and 500.");
  }
  const batches = [];
  let batch = [];
  let batchWrites = 0;
  for (const item of items) {
    const writeCount = item?.writeCount;
    if (!Number.isInteger(writeCount) || writeCount < 1) {
      throw new RangeError("Every scheduled item needs a positive writeCount.");
    }
    if (writeCount > maxWrites) {
      throw new RangeError(
        `Scheduled item ${item.id ?? "unknown"} exceeds the safe write cap.`,
      );
    }
    if (batchWrites + writeCount > maxWrites) {
      batches.push(batch);
      batch = [];
      batchWrites = 0;
    }
    batch.push(item);
    batchWrites += writeCount;
  }
  if (batch.length > 0) batches.push(batch);
  return batches;
}

async function drainPagedJob({
  loadPage,
  processPage,
  inspectBacklog,
  nowMillis = Date.now,
  timeBudgetMs = 7 * 60 * 1000,
  pageSize = 200,
}) {
  if (typeof loadPage !== "function" || typeof processPage !== "function") {
    throw new TypeError("loadPage and processPage are required.");
  }
  const startedAt = nowMillis();
  let processedCount = 0;
  let errorCount = 0;
  let pageCount = 0;
  let cursor = null;
  let exhausted = false;

  while (nowMillis() - startedAt < timeBudgetMs) {
    const items = await loadPage({ cursor, limit: pageSize });
    if (!Array.isArray(items) || items.length === 0) {
      exhausted = true;
      break;
    }
    const result = await processPage(items);
    processedCount += result?.processed ?? 0;
    errorCount += result?.errors ?? 0;
    pageCount += 1;
    cursor = result?.cursor ?? items.at(-1)?.cursor ?? items.at(-1)?.id ?? null;
    if ((result?.processed ?? 0) === 0 && (result?.errors ?? 0) > 0) {
      break;
    }
    if (items.length < pageSize && items.pageFull !== true) {
      exhausted = true;
      break;
    }
  }

  const inspectedAt = nowMillis();
  const backlog = typeof inspectBacklog === "function"
    ? await inspectBacklog()
    : {};
  const oldestEligibleAtMillis = Number.isFinite(
    backlog.oldestEligibleAtMillis,
  )
    ? backlog.oldestEligibleAtMillis
    : null;
  return {
    processedCount,
    errorCount,
    pageCount,
    cursor,
    exhausted,
    stoppedForTimeBudget: !exhausted &&
      inspectedAt - startedAt >= timeBudgetMs,
    backlogCount: Number.isInteger(backlog.backlogCount)
      ? backlog.backlogCount
      : null,
    oldestAgeMs: oldestEligibleAtMillis == null
      ? null
      : Math.max(0, inspectedAt - oldestEligibleAtMillis),
  };
}

module.exports = {
  SAFE_COMMIT_WRITE_LIMIT,
  buildWriteBatches,
  drainPagedJob,
};
