"use strict";

/**
 * Returns whether a group may accept member activity at the supplied instant.
 *
 * The scheduled lifecycle job is intentionally best-effort. Keeping the
 * timestamp window at the callable boundary prevents a stale `active` value
 * from accepting writes after the configured end date (or before a future
 * start date) while the next scheduler run is pending.
 */
function readOptionalTimestampMillis(group, field) {
  if (!Object.prototype.hasOwnProperty.call(group, field)) return null;
  const value = group[field];
  if (!value || typeof value.toMillis !== "function") return undefined;
  let millis;
  try {
    millis = value.toMillis();
  } catch {
    return undefined;
  }
  return Number.isFinite(millis) ? millis : undefined;
}

function isGroupEffectivelyActive(group, nowMillis = Date.now()) {
  if (!group || group.lifecycle !== "active") return false;

  const startMillis = readOptionalTimestampMillis(group, "startDate");
  if (startMillis === undefined) return false;
  if (startMillis !== null && nowMillis < startMillis) return false;

  const endMillis = readOptionalTimestampMillis(group, "endDate");
  if (endMillis === undefined) return false;
  if (endMillis !== null && nowMillis >= endMillis) return false;

  return true;
}

module.exports = {
  isGroupEffectivelyActive,
};
