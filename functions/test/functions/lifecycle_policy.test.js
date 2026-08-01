const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");
const {
  isGroupEffectivelyActive,
} = require("../../lib/lifecycle_policy");

const at = (millis) => Timestamp.fromMillis(millis);

describe("effective group lifecycle policy", () => {
  const nowMillis = 1_000_000;

  test("requires the persisted lifecycle to be active", () => {
    assert.equal(
      isGroupEffectivelyActive({ lifecycle: "scheduled" }, nowMillis),
      false,
    );
    assert.equal(
      isGroupEffectivelyActive({ lifecycle: "completed" }, nowMillis),
      false,
    );
  });

  test("rejects stale active groups after their end date", () => {
    assert.equal(
      isGroupEffectivelyActive({
        lifecycle: "active",
        endDate: at(nowMillis),
      }, nowMillis),
      false,
    );
    assert.equal(
      isGroupEffectivelyActive({
        lifecycle: "active",
        endDate: at(nowMillis + 1),
      }, nowMillis),
      true,
    );
  });

  test("rejects active documents before a future start date", () => {
    assert.equal(
      isGroupEffectivelyActive({
        lifecycle: "active",
        startDate: at(nowMillis + 1),
      }, nowMillis),
      false,
    );
  });

  test("keeps legacy active groups without dates compatible", () => {
    assert.equal(
      isGroupEffectivelyActive({ lifecycle: "active" }, nowMillis),
      true,
    );
  });

  test("rejects an active group with a malformed start date", () => {
    assert.equal(
      isGroupEffectivelyActive({
        lifecycle: "active",
        startDate: "not-a-timestamp",
      }, nowMillis),
      false,
    );
  });

  test("rejects an active group with a malformed end date", () => {
    assert.equal(
      isGroupEffectivelyActive({
        lifecycle: "active",
        endDate: "not-a-timestamp",
      }, nowMillis),
      false,
    );
  });
});
