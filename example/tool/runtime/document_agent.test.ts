import assert from "node:assert/strict";
import { test } from "node:test";
import { documentPrompt, stateOf } from "./document_agent.ts";

test("puts the current document in the prompt", () => {
  const prompt = documentPrompt("Line one.\n\nLine two.");

  assert.match(prompt, /complete new document only/);
  assert.match(prompt, /<document>\nLine one\.\n\nLine two\.\n<\/document>$/);
});

test("keeps an object state and drops anything else", () => {
  assert.deepEqual(stateOf({ document: "a", todos: [] }), {
    document: "a",
    todos: [],
  });
  assert.deepEqual(stateOf(null), {});
  assert.deepEqual(stateOf([1, 2]), {});
  assert.deepEqual(stateOf("text"), {});
});
