"use strict";

/**
 * Returns whether a group may accept member activity at the supplied instant.
 *
 * The scheduled lifecycle job is intentionally best-effort. Keeping the
 * timestamp window at the callable boundary prevents a stale `active` value
 * from accepting writes after the configured end date (or before a future
 * start date) while the next scheduler run is pending.
 */
function isGroupEffectivelyActive(group, nowMillis = Date.now()) {
  if (!group || group.lifecycle !== "active") return false;

  const startMillis = group.startDate?.toMillis?.();
  if (Number.isFinite(startMillis) && nowMillis < startMillis) return false;

  const endMillis = group.endDate?.toMillis?.();
  if (Number.isFinite(endMillis) && nowMillis >= endMillis) return false;

  return true;
}

module.exports = {
  isGroupEffectivelyActive,
};
