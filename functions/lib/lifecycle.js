const DEFAULT_MAX_BATCH_WRITES = 450;

async function commitLifecycleUpdates({
  firestore,
  scheduledDocuments,
  activeDocuments,
  now,
  maxBatchWrites = DEFAULT_MAX_BATCH_WRITES,
}) {
  if (
    !Number.isInteger(maxBatchWrites)
    || maxBatchWrites < 1
    || maxBatchWrites > 500
  ) {
    throw new RangeError("maxBatchWrites must be between 1 and 500.");
  }

  const updates = [
    ...scheduledDocuments.map((document) => ({
      reference: document.ref,
      values: {
        lifecycle: "active",
        activatedAt: now,
      },
    })),
    ...activeDocuments.map((document) => ({
      reference: document.ref,
      values: {
        lifecycle: "completed",
        completedAt: now,
      },
    })),
  ];

  let batchCount = 0;
  for (let offset = 0; offset < updates.length; offset += maxBatchWrites) {
    const batch = firestore.batch();
    for (const update of updates.slice(offset, offset + maxBatchWrites)) {
      batch.update(update.reference, update.values);
    }
    await batch.commit();
    batchCount += 1;
  }

  return {
    activatedCount: scheduledDocuments.length,
    completedCount: activeDocuments.length,
    batchCount,
  };
}

module.exports = {
  commitLifecycleUpdates,
};
