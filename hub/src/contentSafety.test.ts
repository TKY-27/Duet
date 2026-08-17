import assert from "node:assert/strict";
import { test } from "node:test";
import { assertSafeCoordinationMessage } from "./contentSafety.js";

function rejects(message: string): boolean {
  try {
    assertSafeCoordinationMessage(message);
    return false;
  } catch {
    return true;
  }
}

test("rejects provider-specific secret formats", () => {
  assert.ok(rejects("creds AKIA1234567890ABCDEF here"), "AWS access key id");
  assert.ok(rejects("key=AIzaSyB1234567890abcdefghijklmnopqrstuv"), "Google API key");
  assert.ok(rejects("github_pat_11ABCDE0000aBcDeFgHiJ_kLmNoPqRsTuVwXyZ012345"), "GitHub fine-grained PAT");
  assert.ok(rejects("stripe sk_live_0123456789abcdefABCDEF"), "Stripe live key");
  assert.ok(rejects("post to https://hooks.slack.com/services/T000/B000/abcXYZ"), "Slack webhook");
  assert.ok(
    rejects("token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF1234567890"),
    "JWT",
  );
  assert.ok(rejects("blob c2VjcmV0LXZhbHVlLXRoYXQtaXMtbG9uZy1lbm91Z2g="), "padded base64 secret");
});

test("does not flag a natural-language message that cites a commit SHA", () => {
  // A 40-char hex SHA must not trip the high-entropy / base64 heuristics — agents cite
  // these constantly in coordination messages.
  assert.ok(
    !rejects("Reviewed the change at commit a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 — looks good."),
    "commit SHA is allowed",
  );
});

test("rejects two strong code lines but allows prose with operators", () => {
  assert.ok(rejects("const x = 1;\nfunction foo() {"), "two strong code lines");
  assert.ok(
    !rejects("I added the guard in src/foo.ts (early return).\nPlease confirm timeout = 50 is intended."),
    "prose mentioning code is allowed",
  );
});
