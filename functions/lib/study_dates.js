"use strict";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_STUDY_DAYS = 365;

/**
 * Returns the UTC calendar-day number for an epoch millisecond value.
 *
 * The create-study API receives instants, but a study's dates are calendar
 * dates. Comparing raw instants makes same-day values and daylight-saving
 * transitions behave differently from the date picker. Normalizing to a
 * calendar day keeps the server contract deterministic.
 */
function utcCalendarDay(millis) {
  if (!Number.isInteger(millis)) return null;
  const date = new Date(millis);
  if (Number.isNaN(date.getTime())) return null;
  return Math.floor(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
  ) / DAY_MS);
}

function dateKeyCalendarDay(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }
  const [year, month, day] = value.split("-").map(Number);
  const millis = Date.UTC(year, month - 1, day);
  const date = new Date(millis);
  if (
    Number.isNaN(date.getTime())
    || date.getUTCFullYear() !== year
    || date.getUTCMonth() !== month - 1
    || date.getUTCDate() !== day
  ) {
    return null;
  }
  return Math.floor(millis / DAY_MS);
}

/**
 * Returns a stable validation issue or null when a study date range is valid.
 *
 * `reason` is a machine-readable boundary for clients. `message` is retained
 * for server logs/legacy clients, while modern clients use the reason to
 * choose their own field-level copy.
 */
function studyDateRangeIssue({
  startDateMillis,
  endDateMillis,
  startDateKey,
  endDateKey,
} = {}) {
  // The timestamps are still required because they are written to the group
  // document and drive lifecycle scheduling. New clients also send explicit
  // date keys so validation does not reinterpret a local picker date in UTC.
  if (!Number.isInteger(startDateMillis) || !Number.isInteger(endDateMillis)) {
    return {
      reason: "missing",
      message: "startDate and endDate are required",
    };
  }
  const hasStartKey = startDateKey != null;
  const hasEndKey = endDateKey != null;
  if (hasStartKey !== hasEndKey) {
    return {
      reason: "invalid",
      message: "startDateKey and endDateKey must be provided together",
    };
  }
  // Older clients remain supported through the UTC-instant fallback.
  const startDay = hasStartKey
    ? dateKeyCalendarDay(startDateKey)
    : utcCalendarDay(startDateMillis);
  const endDay = hasEndKey
    ? dateKeyCalendarDay(endDateKey)
    : utcCalendarDay(endDateMillis);
  if (startDay === null || endDay === null) {
    return {
      reason: "invalid",
      message: "startDate and endDate must be valid calendar dates",
    };
  }
  const durationDays = endDay - startDay;
  if (durationDays <= 0) {
    return {
      reason: "end-before-or-same-day",
      message: "endDate must be after startDate",
    };
  }
  if (durationDays > MAX_STUDY_DAYS) {
    return {
      reason: "too-long",
      message: "A study cannot run longer than 365 days",
    };
  }
  return null;
}

module.exports = {
  DAY_MS,
  MAX_STUDY_DAYS,
  dateKeyCalendarDay,
  studyDateRangeIssue,
  utcCalendarDay,
};
