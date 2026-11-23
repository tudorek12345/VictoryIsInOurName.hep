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
