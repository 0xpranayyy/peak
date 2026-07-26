import { test } from "node:test";
import assert from "node:assert/strict";
import { isFromEdge, regionStatus, shouldRefuseForRegion } from "../regionGate.mjs";

/** Imports the real implementation — an earlier version of this test mirrored
 *  the logic, which would have passed even if the server changed. */

test("edge gate is fail-safe when no secret is configured", () => {
  assert.equal(isFromEdge({}, undefined), true, "must not lock users out mid-rollout");
  assert.equal(isFromEdge({}, ""), true);
});

test("edge gate admits only the matching secret once configured", () => {
  assert.equal(isFromEdge({ "x-peak-edge-secret": "s3cret" }, "s3cret"), true);
  assert.equal(isFromEdge({ "x-peak-edge-secret": "wrong" }, "s3cret"), false);
  assert.equal(isFromEdge({}, "s3cret"), false, "a direct origin call sends no header");
  assert.equal(isFromEdge({ "x-peak-edge-secret": "x" }, "longer-secret"), false);
});

test("region status only trusts known verdicts", () => {
  assert.equal(regionStatus({ "x-peak-region-status": "blocked" }), "blocked");
  assert.equal(regionStatus({ "x-peak-region-status": "CLOSE_ONLY" }), "close_only");
  assert.equal(regionStatus({}), "unknown");
  assert.equal(regionStatus({ "x-peak-region-status": "garbage" }), "unknown");
});

test("blocked regions may neither open nor close", () => {
  const h = { "x-peak-region-status": "blocked" };
  assert.equal(shouldRefuseForRegion(h, { opening: true }), true);
  assert.equal(shouldRefuseForRegion(h, { opening: false }), true);
});

test("close-only regions may exit a position but not open one", () => {
  const h = { "x-peak-region-status": "close_only" };
  assert.equal(shouldRefuseForRegion(h, { opening: true }), true, "no new positions");
  assert.equal(
    shouldRefuseForRegion(h, { opening: false }),
    false,
    "must be able to sell — trapping users in positions they may legally exit is worse"
  );
});

test("allowed and unknown both pass; CLOB still enforces", () => {
  for (const status of ["allowed", "garbage", undefined]) {
    const h = status ? { "x-peak-region-status": status } : {};
    assert.equal(shouldRefuseForRegion(h, { opening: true }), false);
  }
});
