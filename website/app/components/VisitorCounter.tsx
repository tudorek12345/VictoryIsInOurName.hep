"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { VisitStats } from "../lib/visits";

const SESSION_KEY = "leonida:visit-session:v1";
const BROWSER_KEY = "leonida:anonymous-browser:v1";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function visitIdentity(): { requestId: string; browserId: string | null } | null {
  let requestId: string;
  try {
    const stored = sessionStorage.getItem(SESSION_KEY);
    requestId = stored && UUID.test(stored) ? stored : crypto.randomUUID();
    sessionStorage.setItem(SESSION_KEY, requestId);
  } catch { return null; }
  let browserId: string | null = null;
  try {
    const stored = localStorage.getItem(BROWSER_KEY);
    browserId = stored && UUID.test(stored) ? stored : crypto.randomUUID();
    localStorage.setItem(BROWSER_KEY, browserId);
  } catch { browserId = null; }
  return { requestId, browserId };
}

export default function VisitorCounter({ className = "" }: { className?: string }) {
  const [stats, setStats] = useState<VisitStats | null>(null);
  const [busy, setBusy] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [storageAvailable, setStorageAvailable] = useState(true);
  const request = useRef<AbortController | null>(null);

  const load = useCallback(async () => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    const timer = setTimeout(() => controller.abort(), 8000);
    setBusy(true);
    const identity = visitIdentity();
    setStorageAvailable(Boolean(identity));
    try {
      const response = await fetch("/api/visits", {
        method: identity ? "POST" : "GET",
        headers: identity ? { "Content-Type": "application/json" } : undefined,
        body: identity ? JSON.stringify(identity) : undefined,
        cache: "no-store",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("counter_unavailable");
      const data = await response.json() as VisitStats;
      if (data.available !== true || !Number.isSafeInteger(data.views) || data.views < 0 || !Number.isSafeInteger(data.uniqueBrowsers) || data.uniqueBrowsers < 0) throw new Error("counter_unavailable");
      if (!controller.signal.aborted) { setStats(data); setUnavailable(false); }
    } catch {
      if (request.current === controller) setUnavailable(true);
    } finally {
      clearTimeout(timer);
      if (request.current === controller) setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load();
    return () => { request.current?.abort(); request.current = null; };
  }, [load]);

  const started = stats?.firstRecordedAt ? new Date(stats.firstRecordedAt).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }) : null;

  return (
    <section className={`visitor-counter terminal-counter ${className}`.trim()} aria-label="Recorded site visits">
      <div className="visitor-counter__heading"><span>Community reach</span><span>Recorded on this site</span></div>
      <div className="visitor-counter__metrics" aria-live="polite" aria-atomic="true">
        <div className="visitor-counter__metric">
          <strong className="visitor-counter__value">{stats ? stats.views.toLocaleString("en-US") : "—"}</strong>
          <span className="visitor-counter__label">All-time recorded views</span>
        </div>
        <div className="visitor-counter__metric">
          <strong className="visitor-counter__value">{stats ? stats.uniqueBrowsers.toLocaleString("en-US") : "—"}</strong>
          <span className="visitor-counter__label">Unique browsers</span>
        </div>
      </div>
      {unavailable ? <p className="visitor-counter__unavailable" role="status">{stats ? "Showing the last count loaded. Refresh is temporarily unavailable." : "The counter is temporarily unavailable."}</p> : busy && !stats ? <p className="visitor-counter__detail">Loading recorded visits…</p> : <p className="visitor-counter__detail">{started ? `Counting since ${started} · UTC` : "Tracking starts with the first recorded visit."}</p>}
      <details className="visitor-counter__methodology">
        <summary>How visits are counted</summary>
        <p>One recorded view per browser tab session. Reloads and request retries do not add views. Unique browsers use a random ID saved in that browser; they are not a count of people. Clearing storage or using another browser creates a new ID. No IP addresses, user agents, or fingerprints are stored.</p>
        {!storageAvailable && <p>Browser session storage is unavailable, so this visit has not been recorded.</p>}
        <p>Totals start when this counter records its first visit. Earlier traffic is not included.</p>
      </details>
      <button type="button" className="visitor-counter__refresh" disabled={busy} onClick={() => void load()}>{busy ? "Updating…" : "Refresh count"}</button>
    </section>
  );
}
