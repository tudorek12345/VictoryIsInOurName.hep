"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { VisitStats } from "../lib/visits";
import "./visitor-counter-live.css";

const SESSION_KEY = "leonida:visit-session:v1";
const BROWSER_KEY = "leonida:anonymous-browser:v1";
const RECORDED_KEY = "leonida:visit-confirmed:v1";
const REFRESH_MS = 30_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Identity = { requestId: string; browserId: string | null };
type RegistrationState = "pending" | "confirmed" | "unconfirmed" | "storage-unavailable";
type RequestResult = "success" | "failure" | "cancelled" | "busy";

function visitIdentity(): Identity | null {
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

function alreadyConfirmed(identity: Identity): boolean {
  try { return sessionStorage.getItem(RECORDED_KEY) === identity.requestId; }
  catch { return false; }
}

function confirmVisit(identity: Identity) {
  try { sessionStorage.setItem(RECORDED_KEY, identity.requestId); }
  catch { /* A future retry still uses the same idempotent session UUID. */ }
}

function validStats(value: unknown): value is VisitStats {
  if (!value || typeof value !== "object") return false;
  const data = value as Partial<VisitStats>;
  return data.available === true
    && Number.isSafeInteger(data.views) && data.views! >= 0
    && Number.isSafeInteger(data.uniqueBrowsers) && data.uniqueBrowsers! >= 0
    && (data.firstRecordedAt === null || (typeof data.firstRecordedAt === "string" && !Number.isNaN(Date.parse(data.firstRecordedAt))));
}

export default function VisitorCounter({ className = "" }: { className?: string }) {
  const [stats, setStats] = useState<VisitStats | null>(null);
  const [busy, setBusy] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [registration, setRegistration] = useState<RegistrationState>("pending");
  const [lastUpdated, setLastUpdated] = useState<number | null>(null);
  const request = useRef<AbortController | null>(null);
  const generation = useRef(0);

  const fetchCount = useCallback(async (method: "GET" | "POST", expectedGeneration: number, identity?: Identity): Promise<RequestResult> => {
    if (generation.current !== expectedGeneration) return "cancelled";
    // Keep requests sequential. A late read must never overwrite a newer POST
    // response, and interval/manual refreshes must not abort registration.
    if (request.current) return "busy";
    const controller = new AbortController();
    request.current = controller;
    const timer = setTimeout(() => controller.abort(), 8000);
    setBusy(true);
    try {
      const response = await fetch("/api/visits", {
        method,
        headers: method === "POST" ? { "Content-Type": "application/json" } : undefined,
        body: method === "POST" ? JSON.stringify(identity) : undefined,
        cache: "no-store",
        signal: controller.signal,
      });
      if (!response.ok) throw new Error("counter_unavailable");
      const data: unknown = await response.json();
      if (!validStats(data)) throw new Error("counter_unavailable");
      if (generation.current !== expectedGeneration) return "cancelled";
      if (controller.signal.aborted) throw new Error("counter_unavailable");
      setStats(data);
      setLastUpdated(Date.now());
      setUnavailable(false);
      return "success";
    } catch {
      if (generation.current !== expectedGeneration) return "cancelled";
      if (method === "GET") setUnavailable(true);
      return "failure";
    } finally {
      clearTimeout(timer);
      if (request.current === controller) {
        request.current = null;
        if (generation.current === expectedGeneration) setBusy(false);
      }
    }
  }, []);

  useEffect(() => {
    const currentGeneration = ++generation.current;
    const identity = visitIdentity();
    const confirmed = identity !== null && alreadyConfirmed(identity);
    setRegistration(identity === null ? "storage-unavailable" : confirmed ? "confirmed" : "pending");

    const start = async () => {
      // Show the existing durable total before attempting to count this tab.
      await fetchCount("GET", currentGeneration);
      if (generation.current !== currentGeneration || !identity || confirmed) return;
      const result = await fetchCount("POST", currentGeneration, identity);
      if (generation.current !== currentGeneration) return;
      if (result === "success") {
        confirmVisit(identity);
        setRegistration("confirmed");
      } else if (result === "failure") {
        // A POST may have committed even if its response was lost. Do not claim
        // the visit was definitely unrecorded or generate another session ID.
        setRegistration("unconfirmed");
        await fetchCount("GET", currentGeneration);
      }
    };
    void start();

    const refreshIfVisible = () => {
      if (document.visibilityState === "visible") void fetchCount("GET", currentGeneration);
    };
    const interval = setInterval(refreshIfVisible, REFRESH_MS);
    document.addEventListener("visibilitychange", refreshIfVisible);
    window.addEventListener("pageshow", refreshIfVisible);
    return () => {
      generation.current++;
      clearInterval(interval);
      document.removeEventListener("visibilitychange", refreshIfVisible);
      window.removeEventListener("pageshow", refreshIfVisible);
      request.current?.abort();
      request.current = null;
    };
  }, [fetchCount]);

  const started = stats?.firstRecordedAt ? new Date(stats.firstRecordedAt).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }) : null;
  const updatedLabel = lastUpdated === null ? null : new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit", timeZoneName: "short" }).format(lastUpdated);

  return (
    <section className={`visitor-counter terminal-counter ${className}`.trim()} aria-label="Recorded site visits">
      <div className="visitor-counter__heading"><span>Community reach</span><span>Recorded site traffic</span></div>
      <div className="visitor-counter__metrics" aria-live="polite" aria-atomic="true">
        <div className="visitor-counter__metric">
          <strong className="visitor-counter__value">{stats ? stats.views.toLocaleString("en-US") : "—"}</strong>
          <span className="visitor-counter__label">All-time recorded visits</span>
        </div>
        <div className="visitor-counter__metric">
          <strong className="visitor-counter__value">{stats ? stats.uniqueBrowsers.toLocaleString("en-US") : "—"}</strong>
          <span className="visitor-counter__label">Unique browsers</span>
        </div>
      </div>
      <div className="visitor-counter__meta">
        <p className="visitor-counter__detail">{stats ? started ? `Counting since ${started} · UTC` : "Tracking starts with the first recorded visit." : busy ? "Loading recorded visits…" : "Stored totals are not currently available."}</p>
        {lastUpdated !== null && <p className="visitor-counter__updated">Updated <time dateTime={new Date(lastUpdated).toISOString()}>{updatedLabel}</time> · your local time</p>}
        <p className="visitor-counter__frequency">Refreshes every 30 seconds while this tab is visible.</p>
      </div>
      <button type="button" className="visitor-counter__refresh" disabled={busy} onClick={() => void fetchCount("GET", generation.current)}>{busy ? "Updating…" : "Refresh count"}</button>
      {unavailable && <p className="visitor-counter__unavailable" role="status">{stats ? "Showing the last count loaded. Refresh is temporarily unavailable." : "The counter is temporarily unavailable. No estimated total is shown."}</p>}
      {registration === "unconfirmed" && <p className="visitor-counter__registration" role="status">This tab’s visit could not be confirmed. Read-only refreshes still show the stored total.</p>}
      <details className="visitor-counter__methodology">
        <summary>How visits are counted</summary>
        <p>One recorded visit per browser tab session. Reloads and request retries do not add visits. Automatic and manual refreshes only read the count. Unique browsers use a random ID saved in that browser; they are not a count of people. Clearing storage or using another browser creates a new ID. No IP addresses, user agents, or fingerprints are stored.</p>
        {registration === "storage-unavailable" && <p>Browser session storage is unavailable, so this tab has not been registered.</p>}
        <p>Totals retain the site’s existing recorded history from the first date shown. Traffic from before the counter was introduced is not included.</p>
      </details>
    </section>
  );
}
