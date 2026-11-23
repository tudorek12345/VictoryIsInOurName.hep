import test from "node:test";
import assert from "node:assert/strict";
import { createEmptyDraft, FIELD_LIMITS, getReadiness, parseStoredDraft, serializeDraft, toHandoffMarkdown } from "../app/lib/workbench.ts";

test("an empty draft starts at zero and exports no claimed outcome", () => {
  const draft = createEmptyDraft();
  assert.equal(getReadiness(draft).filter(item => item.complete).length, 0);
  const markdown = toHandoffMarkdown(draft);
  assert.match(markdown, /No outcome recorded\. This draft contains no test result\./);
  assert.match(markdown, /Local preparation: 0 \/ 5/);
  assert.match(markdown, /not game compatibility/);
});

test("readiness requires an actual baseline, environment and explicit result check", () => {
  const draft = { ...createEmptyDraft("graphics"), baseline: "a".repeat(40), environment: "Windows / test GPU", hypothesis: "A mapped page may be missing.", command: "run the local fixture", expected: "Both mappings expose the same data.", observed: "The fixture reported a mismatch.", nextStep: "Inspect the backing allocation." };
  assert.equal(getReadiness(draft).filter(item => item.complete).length, 4);
  assert.equal(getReadiness({ ...draft, resultChecked: true }).filter(item => item.complete).length, 5);
  assert.equal(getReadiness({ ...draft, environment: " " })[0].complete, false);
  assert.equal(getReadiness({ ...draft, baseline: "main" })[0].complete, false);
  assert.equal(getReadiness({ ...draft, observed: "", resultChecked: true })[3].complete, false);
});

test("stored drafts round-trip, bound untrusted values and reject invalid envelopes", () => {
  const draft = { ...createEmptyDraft("reproduction"), hypothesis: "Reproduce a failure.", command: "fixture.exe" };
  assert.deepEqual(parseStoredDraft(serializeDraft(draft)), draft);
  for (const raw of [null, "{", "[]", JSON.stringify({ version: 2, draft }), "x".repeat(20_001)]) assert.equal(parseStoredDraft(raw), null);
  const bounded = parseStoredDraft(JSON.stringify({ version: 1, draft: { investigation: "unknown", hypothesis: "a".repeat(5000), observed: { bad: true }, environment: "OS\nGPU", resultChecked: "true" } }));
  assert.equal(bounded.investigation, "loader");
  assert.equal(bounded.hypothesis.length, FIELD_LIMITS.hypothesis);
  assert.equal(bounded.observed, "");
  assert.equal(bounded.environment, "OS GPU");
  assert.equal(bounded.resultChecked, false);
});

test("Markdown preserves multiline commands without letting embedded backticks close their fence", () => {
  const draft = { ...createEmptyDraft(), command: "echo first\n```\necho last", observed: "Failure recorded.\nNext diagnostic line.", resultChecked: true };
  const markdown = toHandoffMarkdown(draft);
  assert.match(markdown, /````text\necho first\n```\necho last\n````/);
  assert.match(markdown, /> Failure recorded\.\n> Next diagnostic line\./);
  assert.match(markdown, /Yes \(self-reported\)/);
});
