"use client";

import { useState } from "react";
import "./christmas-banner.css";

const MESSAGE = "XMAS PRESENT FROM CBRLK MAYBE? LET’S SEE IF IT RUNS";

function PixelGift() {
  return (
    <svg className="christmas-banner__gift" width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true" focusable="false" shapeRendering="crispEdges">
      <path d="M3 9h14v9H3zM2 6h16v4H2z" fill="currentColor" />
      <path d="M9 6h2v12H9zM2 9h16v1H2z" fill="#17272d" />
      <path d="M5 2h4v2H7v2H5V2zm6 0h4v4h-2V4h-2V2zM9 4h2v2H9z" fill="var(--amber, #ffd08a)" />
    </svg>
  );
}

function BannerMessage() {
  return (
    <span className="christmas-banner__item">
      <PixelGift />
      <span>{MESSAGE}</span>
      <span className="christmas-banner__star" aria-hidden="true">✦</span>
    </span>
  );
}

export default function ChristmasBanner() {
  const [paused, setPaused] = useState(false);

  return (
    <aside className={`christmas-banner page-width${paused ? " christmas-banner--paused" : ""}`} aria-label="Christmas project note">
      <p className="christmas-banner__sr-only">{MESSAGE}</p>
      <div className="christmas-banner__viewport" aria-hidden="true">
        <div className="christmas-banner__track">
          {[0, 1].map(group => (
            <div className="christmas-banner__group" key={group}>
              <BannerMessage />
              <BannerMessage />
            </div>
          ))}
        </div>
      </div>
      <div className="christmas-banner__static" aria-hidden="true">
        <PixelGift />
        <p>{MESSAGE}</p>
      </div>
      <button
        type="button"
        className="christmas-banner__toggle"
        aria-pressed={paused}
        aria-label={paused ? "Resume Christmas banner animation" : "Pause Christmas banner animation"}
        title="Hovering or keyboard focus also pauses all banner animation."
        onClick={() => setPaused(value => !value)}
      >
        <span className={paused ? "christmas-banner__play-icon" : "christmas-banner__pause-icon"} aria-hidden="true" />
        {paused ? "Resume" : "Pause"}
      </button>
    </aside>
  );
}
