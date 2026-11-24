/** Maintainer-supplied report, published 23 November 2026. Not a compatibility claim. */
export const SHOWCASE_EVENT_URL = "https://discord.com/events/1459617753907331094/1574557419596677260";

export const PROGRESS_UPDATE = {
  date: "2026-11-23",
  environment: "Windows 11 · AMD RX 9070 XT",
  scope: "Maintainer-reported results from one machine; not independently reproduced or verified across other hardware.",
  credit: "Huge respect to Marvis for the ongoing code research and collaboration. This research programme is committed to working under applicable law.",
  stages: [
    { id: "first-boot", shortLabel: "First boot", status: "working", stage: "Boot and first-boot screens", state: "Works · 30 fps", detail: "Accessibility, language, settings and legal screens." },
    { id: "intro", shortLabel: "Video + audio", status: "working", stage: "Intro video with sound", state: "Works", detail: "Video playback and sound are reported working." },
    { id: "profile", shortLabel: "Profile + saves", status: "working", stage: "Start screen, profile and saves", state: "Works", detail: "Start screen, profile and save flow are reported working." },
    { id: "loading", shortLabel: "World loading", status: "working", stage: "Loading into the world", state: "Works · about 50 s", detail: "The reported load reaches the first mission’s intro." },
    { id: "world", shortLabel: "World rendering", status: "blocked", stage: "World / first mission’s intro", state: "Reached · blocked", detail: "The picture is black and the host GPU fails within seconds." },
  ],
  nextSteps: [
    { id: "capture", status: "next", title: "Capture the exact tested build", detail: "Record the runtime revision, local changes, GPU driver and reproduction steps." },
    { id: "render", status: "next", title: "Resolve the world-rendering failure", detail: "Trace the black image and host GPU failure, then reach a correctly rendered, stable world frame." },
    { id: "reproduce", status: "next", title: "Reproduce on another machine", detail: "Repeat the documented run independently before expanding compatibility claims." },
  ],
} as const;

/** Separate runtime update; the 23 November stage report above keeps its original provenance. */
export const RECENT_RUNTIME_UPDATE = {
  timestamp: "2026-11-24T03:00:00-05:00",
  label: "24 November 2026, 03:00 EST (UTC−05:00)",
  environment: "AMD Radeon RX 9060 XT 16GB · AMD Ryzen 7 5700X · 32GB RAM",
  scope: "Maintainer-reported runtime work on this machine; controllable hardware gameplay remains unverified.",
  changes: [
    "Raw bindless SRV consistency.",
    "Typed UINT16 UAV support.",
    "Exact 3:1 compositor downscaling and concurrent cache-fill coalescing.",
    "Caller, fence and Present diagnostics.",
  ],
  performance: {
    scope: "Short intro only; no gameplay.",
    hardware: { fps: 30, frameTimeMs: 33.3 },
    warp: { fps: 10, frameTimeMs: 100, approximate: true },
  },
  checklist: [
    { id: "single-list-removal", status: "completed", title: "Trace single-list device removal", detail: "Single-list device removal traced; the remaining defect is not yet attributed." },
    { id: "failure-path-diagnostics", status: "completed", title: "Distinguish failure paths and retain the fence phase", detail: "Caller/fence/Present instrumentation is implemented to distinguish failure paths and retain the fence phase; defect attribution remains pending." },
    { id: "serial-reproduction", status: "partial", title: "Serial build, tests and debug reproduction", detail: "Serial build succeeded; 303 workspace tests passed, 5 ignored (GPU crate: 62 passed, 2 ignored). Original-file protection checks passed. The latest debug request could not enable the missing debug layer and exited with code 0 after 28.42 s, before reaching the world. This does not verify a successful world run." },
    { id: "hardware-gameplay", status: "pending", title: "Fix the demonstrated remaining defect and verify controllable hardware gameplay", detail: "The remaining defect still needs a demonstrated fix followed by controllable gameplay verification on hardware." },
  ],
} as const;
