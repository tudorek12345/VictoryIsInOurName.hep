"use client";

import { useState } from "react";
import { SHOWCASE_EVENT_URL } from "../lib/progress-update";
import "./showcase-alert.css";

function WarningMark() {
  return (
    <svg width="18" height="17" viewBox="0 0 18 17" fill="none" aria-hidden="true" focusable="false">
      <path d="M9 1.5 17 15.5H1L9 1.5Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M9 6v4" stroke="currentColor" strokeWidth="1.5" />
      <rect x="8.25" y="12" width="1.5" height="1.5" fill="currentColor" />
    </svg>
  );
}

export default function ShowcaseAlert() {
  const [paused, setPaused] = useState(false);

  return (
    <section className={`showcase-alert page-width${paused ? " showcase-alert--paused" : ""}`} aria-labelledby="showcase-alert-title">
      <header className="showcase-alert__header">
        <span className="showcase-alert__new"><WarningMark /> NEW UPDATE <WarningMark /></span>
        <button className="showcase-alert__pause" type="button" aria-pressed={paused} onClick={() => setPaused(value => !value)}>
          {paused ? "Resume effects" : "Pause effects"}
        </button>
      </header>
      <div className="showcase-alert__grid">
        <div className="showcase-alert__copy">
          <h2 id="showcase-alert-title">GTA VI port progress showcase</h2>
          <p className="showcase-alert__intro">First-boot screens, the intro video, profiles and saves are reported working. World entry is reached; rendering remains blocked.</p>
          <div className="showcase-alert__date">
            <time dateTime="2026-11-25">Wednesday, 25 November 2026</time>
            <span>See your local time on Discord</span>
          </div>
          <div className="showcase-alert__actions">
            <a className="showcase-alert__join" href={SHOWCASE_EVENT_URL} target="_blank" rel="noopener noreferrer">Join the Discord event</a>
            <a className="showcase-alert__progress" href="#progress-update">Read the progress report</a>
          </div>
        </div>
        <figure className="showcase-alert__figure">
          <div className="showcase-alert__crop">
            <img
              src="/images/showcase-discord.png"
              width={1482}
              height={1133}
              loading="eager"
              decoding="async"
              alt="Discord event card for the GTA VI port progress showcase."
            />
          </div>
          <figcaption><a href="/images/showcase-discord.png" target="_blank" rel="noopener noreferrer">View full screenshot</a></figcaption>
        </figure>
      </div>
    </section>
  );
}
