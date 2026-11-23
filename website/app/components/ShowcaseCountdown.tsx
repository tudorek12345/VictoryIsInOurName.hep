"use client";

import { useEffect, useId, useState } from "react";
import "./showcase-countdown.css";

// Fixed project window: these timestamps never depend on a visitor's first visit.
export const SHOWCASE_COUNTDOWN_START = "2026-11-23T18:55:45.000Z";
export const SHOWCASE_COUNTDOWN_DEADLINE = "2026-11-30T18:55:45.000Z";
const DEADLINE_MS = Date.parse(SHOWCASE_COUNTDOWN_DEADLINE);

function splitRemaining(milliseconds: number) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return {
    days: Math.floor(totalSeconds / 86400),
    hours: Math.floor((totalSeconds % 86400) / 3600),
    minutes: Math.floor((totalSeconds % 3600) / 60),
    seconds: totalSeconds % 60,
  };
}

export default function ShowcaseCountdown() {
  const headingId = useId();
  const [remaining, setRemaining] = useState<number | null>(null);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | undefined;
    const refresh = () => {
      const next = Math.max(0, DEADLINE_MS - Date.now());
      setRemaining(next);
      if (next === 0 && interval !== undefined) {
        clearInterval(interval);
        interval = undefined;
      }
    };
    interval = setInterval(refresh, 1000);
    refresh();

    const onVisibility = () => {
      if (document.visibilityState === "visible") refresh();
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pageshow", refresh);
    return () => {
      if (interval !== undefined) clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pageshow", refresh);
    };
  }, []);

  const parts = remaining === null ? null : splitRemaining(remaining);
  const expired = remaining === 0;
  const timerLabel = parts
    ? `${parts.days} days, ${parts.hours} hours, ${parts.minutes} minutes, ${parts.seconds} seconds remaining until the possible reproducible build showcase target.`
    : "Calculating time remaining until the possible reproducible build showcase target.";
  const units = [
    { label: "Days", value: parts?.days },
    { label: "Hours", value: parts?.hours },
    { label: "Minutes", value: parts?.minutes },
    { label: "Seconds", value: parts?.seconds },
  ];

  return (
    <section className={`showcase-countdown page-width${expired ? " showcase-countdown--complete" : ""}`} aria-labelledby={headingId}>
      <div className="showcase-countdown__copy">
        <h2 id={headingId}><span aria-hidden="true">&gt;_</span> Possible reproducible build showcase</h2>
        <p className="showcase-countdown__target">
          Target: <time dateTime={SHOWCASE_COUNTDOWN_DEADLINE}>30 Nov 2026 · 19:55:45 CET</time>
          <span>Europe/Prague</span>
        </p>
      </div>
      <div className="showcase-countdown__timer" role="timer" aria-live="off" aria-label={timerLabel}>
        {units.map(unit => (
          <div className="showcase-countdown__unit" key={unit.label} aria-hidden="true">
            <span className="showcase-countdown__digits">{unit.value === undefined ? "--" : String(unit.value).padStart(2, "0")}</span>
            <span className="showcase-countdown__label">{unit.label}</span>
          </div>
        ))}
      </div>
      <p className="showcase-countdown__status" role="status" aria-live="polite" aria-atomic="true">
        {expired ? <>Countdown complete — check <a href="https://github.com/tudorek12345/Leonida" target="_blank" rel="noopener noreferrer">GitHub</a> for an update.</> : null}
      </p>
    </section>
  );
}
