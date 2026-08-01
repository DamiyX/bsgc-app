const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  DAY_MS,
  MAX_STUDY_DAYS,
  dateKeyCalendarDay,
  studyDateRangeIssue,
  utcCalendarDay,
} = require("../../lib/study_dates");

function utcMillis(year, month, day, hour = 0) {
  return Date.UTC(year, month - 1, day, hour);
}

describe("study date range contract", () => {
  test("compares calendar days, not raw instants, for same-day inputs", () => {
    const start = utcMillis(2026, 8, 1, 8);
    const endLaterThatDay = utcMillis(2026, 8, 1, 18);

    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: start,
      endDateMillis: endLaterThatDay,
    }), {
      reason: "end-before-or-same-day",
      message: "endDate must be after startDate",
    });
  });

  test("allows exactly the 365-day calendar boundary", () => {
    const start = utcMillis(2026, 8, 1);
    const end = utcMillis(2027, 8, 1);

    assert.equal(utcCalendarDay(end) - utcCalendarDay(start), MAX_STUDY_DAYS);
    assert.equal(studyDateRangeIssue({
      startDateMillis: start,
      endDateMillis: end,
    }), null);
  });

  test("rejects a range beyond the 365-day calendar boundary", () => {
    const start = utcMillis(2026, 8, 1);
    const end = start + (MAX_STUDY_DAYS + 1) * DAY_MS;

    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: start,
      endDateMillis: end,
    }), {
      reason: "too-long",
      message: "A study cannot run longer than 365 days",
    });
  });

  test("requires valid integer date instants", () => {
    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: null,
      endDateMillis: utcMillis(2026, 8, 2),
    }), {
      reason: "missing",
      message: "startDate and endDate are required",
    });
    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: Number.NaN,
      endDateMillis: 1,
    }), {
      reason: "missing",
      message: "startDate and endDate are required",
    });
  });

  test("explicit picker date keys win over timezone-shifted instants", () => {
    const localStart = utcMillis(2026, 7, 31, 23);
    const localEnd = utcMillis(2026, 8, 1, 23);

    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: localStart,
      endDateMillis: localEnd,
      startDateKey: "2026-08-01",
      endDateKey: "2026-08-01",
    }), {
      reason: "end-before-or-same-day",
      message: "endDate must be after startDate",
    });
    assert.equal(dateKeyCalendarDay("2026-08-01"), utcCalendarDay(localEnd));
  });

  test("rejects malformed explicit date keys", () => {
    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: utcMillis(2026, 8, 1),
      endDateMillis: utcMillis(2026, 8, 2),
      startDateKey: "2026-02-30",
      endDateKey: "2026-03-02",
    }), {
      reason: "invalid",
      message: "startDate and endDate must be valid calendar dates",
    });
  });

  test("requires timestamps for the stored group dates", () => {
    assert.deepEqual(studyDateRangeIssue({
      startDateKey: "2026-08-01",
      endDateKey: "2026-08-02",
    }), {
      reason: "missing",
      message: "startDate and endDate are required",
    });
  });

  test("does not accept only one explicit picker key", () => {
    assert.deepEqual(studyDateRangeIssue({
      startDateMillis: utcMillis(2026, 8, 1),
      endDateMillis: utcMillis(2026, 8, 2),
      startDateKey: "2026-08-01",
    }), {
      reason: "invalid",
      message: "startDateKey and endDateKey must be provided together",
    });
  });
});
