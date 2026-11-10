import assert from "node:assert/strict";
import { test } from "node:test";
import {
  defaultLearningContainerId,
  defaultUser,
  identifyDemoUser,
  resolveLearningContainerId,
} from "./config.ts";

test("uses the default container when unset or blank", () => {
  assert.equal(resolveLearningContainerId(undefined), defaultLearningContainerId);
  assert.equal(resolveLearningContainerId("  "), defaultLearningContainerId);
});

test("accepts a valid container id", () => {
  assert.equal(resolveLearningContainerId("expense-review"), "expense-review");
  assert.equal(resolveLearningContainerId("a".repeat(64)), "a".repeat(64));
});

test("rejects invalid container ids", () => {
  for (const id of ["Expense", "a--b", "-a", "a-", "a_b", "a".repeat(65)]) {
    assert.throws(() => resolveLearningContainerId(id), /invalid/, id);
  }
});

test("identifies the user from the demo header", () => {
  const request = new Request("http://x", { headers: { "x-demo-user": "Ada Lovelace" } });
  assert.deepEqual(identifyDemoUser(request), { id: "ada-lovelace", name: "Ada Lovelace" });
});

test("falls back to the default user without the header", () => {
  assert.deepEqual(identifyDemoUser(new Request("http://x")), defaultUser);
});
