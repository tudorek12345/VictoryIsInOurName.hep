export const WORKBENCH_STORAGE_KEY = "leonida:experiment-workbench:v1";

export const WORKBENCH_PRESETS = [
  {
    id: "loader",
    title: "Loader + memory",
    short: "01 / RUNTIME",
    description: "Isolate one startup, TLS or memory-mapping failure.",
    hypothesis: "Which specific runtime behavior could explain the first failure?",
    command: 'gta6rt --dry-run "<executable>" --game-dir "<package>" --overlay "<overlay>"',
    expected: "What would you observe if the loader or memory behavior is correct?",
  },
  {
    id: "graphics",
    title: "Descriptors + graphics",
    short: "02 / GRAPHICS",
    description: "Follow descriptor addresses, resource backing and the first submission.",
    hypothesis: "Which descriptor or CPU/GPU memory relationship needs to be measured?",
    command: 'gta6rt --run "<executable>" --game-dir "<package>" --overlay "<overlay>" --trace "<new-trace.jsonl>" --trace-d3d12',
    expected: "Describe the expected handle, resource contents or next graphics call.",
  },
  {
    id: "reproduction",
    title: "Reproduce + handoff",
    short: "03 / EVIDENCE",
    description: "Make one reported result repeatable on a recorded environment.",
    hypothesis: "Which existing observation are you trying to reproduce or challenge?",
    command: 'python -I tools/boot_trace.py "<startup.jsonl>" --d3d12 "<d3d12.log>"',
    expected: "Name the particular observation that would confirm this reproduction.",
  },
] as const;

export type InvestigationId = typeof WORKBENCH_PRESETS[number]["id"];

export interface ExperimentDraft {
  investigation: InvestigationId;
  hypothesis: string;
  baseline: string;
  environment: string;
  command: string;
  expected: string;
  observed: string;
  nextStep: string;
  resultChecked: boolean;
}

export type DraftTextField = Exclude<keyof ExperimentDraft, "investigation" | "resultChecked">;

export const FIELD_LIMITS: Record<DraftTextField, number> = {
  hypothesis: 1200,
  baseline: 40,
  environment: 300,
  command: 2000,
  expected: 1200,
  observed: 2400,
  nextStep: 1200,
};

export function createEmptyDraft(investigation: InvestigationId = "loader"): ExperimentDraft {
  return {
    investigation,
    hypothesis: "",
    baseline: "",
    environment: "",
    command: "",
    expected: "",
    observed: "",
    nextStep: "",
    resultChecked: false,
  };
}

function boundedText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  // Discard nonprinting control characters while preserving normal line breaks.
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").slice(0, max);
}

export function parseStoredDraft(raw: string | null): ExperimentDraft | null {
  if (!raw || raw.length > 20_000) return null;
  try {
    const saved: unknown = JSON.parse(raw);
    if (!saved || typeof saved !== "object" || Array.isArray(saved)) return null;
    const envelope = saved as Record<string, unknown>;
    if (envelope.version !== 1 || !envelope.draft || typeof envelope.draft !== "object" || Array.isArray(envelope.draft)) return null;
    const input = envelope.draft as Record<string, unknown>;
    const investigation = WORKBENCH_PRESETS.find(preset => preset.id === input.investigation)?.id ?? "loader";
    const result = createEmptyDraft(investigation);
    for (const field of Object.keys(FIELD_LIMITS) as DraftTextField[]) {
      result[field] = boundedText(input[field], FIELD_LIMITS[field]);
    }
    result.baseline = result.baseline.replace(/[\r\n]/g, "");
    result.environment = result.environment.replace(/[\r\n]+/g, " ");
    result.resultChecked = input.resultChecked === true;
    return result;
  } catch {
    return null;
  }
}

export function serializeDraft(draft: ExperimentDraft): string {
  return JSON.stringify({ version: 1, draft });
}

export function isBaselineSha(value: string): boolean {
  return /^[a-f\d]{7,40}$/i.test(value.trim());
}

export function getReadiness(draft: ExperimentDraft) {
  return [
    { id: "baseline", label: "Record baseline + environment", complete: isBaselineSha(draft.baseline) && Boolean(draft.environment.trim()) },
    { id: "hypothesis", label: "Define hypothesis + expectation", complete: Boolean(draft.hypothesis.trim() && draft.expected.trim()) },
    { id: "command", label: "Write the reproduction command", complete: Boolean(draft.command.trim()) },
    { id: "result", label: "Record + check the observed result", complete: Boolean(draft.observed.trim()) && draft.resultChecked },
    { id: "next", label: "Leave a concrete next step", complete: Boolean(draft.nextStep.trim()) },
  ];
}

function note(value: string, fallback: string): string {
  return (value.trim() || fallback).split(/\r?\n/).map(line => `> ${line}`).join("\n");
}

function commandBlock(command: string): string {
  const value = command.trim() || "# Reproduction command not recorded.";
  const longestFence = Math.max(0, ...(value.match(/`+/g) ?? []).map(match => match.length));
  const fence = "`".repeat(Math.max(3, longestFence + 1));
  return `${fence}text\n${value}\n${fence}`;
}

export function toHandoffMarkdown(draft: ExperimentDraft): string {
  const preset = WORKBENCH_PRESETS.find(item => item.id === draft.investigation) ?? WORKBENCH_PRESETS[0];
  const checks = getReadiness(draft);
  const complete = checks.filter(check => check.complete).length;
  return [
    "# Leonida experiment handoff",
    "",
    `Investigation: ${preset.title}`,
    "",
    "Author-entered local draft. Results below are not independently verified or automatically published.",
    "",
    "## Reproduction context",
    "",
    "Repository: https://github.com/tudorek12345/Leonida",
    `Baseline commit: ${isBaselineSha(draft.baseline) ? draft.baseline.trim() : "Not recorded as a valid 7–40 character commit SHA."}`,
    "",
    "Environment / GPU / driver:",
    note(draft.environment, "Not recorded."),
    "",
    "## Hypothesis",
    "",
    note(draft.hypothesis, "No hypothesis recorded."),
    "",
    "## Reproduction command",
    "",
    commandBlock(draft.command),
    "",
    "## Expected outcome",
    "",
    note(draft.expected, "No expected outcome recorded."),
    "",
    "## Observed outcome",
    "",
    note(draft.observed, "No outcome recorded. This draft contains no test result."),
    "",
    `Author checked this result against local evidence: ${draft.resultChecked && draft.observed.trim() ? "Yes (self-reported)." : "Not confirmed."}`,
    "",
    "## Next experiment / handoff",
    "",
    note(draft.nextStep, "Next step not recorded."),
    "",
    `## Local preparation: ${complete} / ${checks.length}`,
    "",
    ...checks.map(check => `- [${check.complete ? "x" : " "}] ${check.label}`),
    "",
    "This checklist measures preparation of this note, not game compatibility, successful execution or a verified game frame.",
    "",
  ].join("\n");
}
