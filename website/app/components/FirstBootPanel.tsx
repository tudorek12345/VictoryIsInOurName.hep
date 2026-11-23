"use client";

import { useId } from "react";
import "./first-boot-panel.css";

export default function FirstBootPanel() {
  const titleId = useId();

  return (
    <figure className="first-boot-panel retro-window" aria-labelledby={titleId}>
      <div className="first-boot-panel__bar window-bar">
        <h2 id={titleId} className="first-boot-panel__title">First Boot</h2>
        <span className="window-controls" aria-hidden="true"><i /><i /><i /></span>
      </div>
      <div className="first-boot-panel__image-wrap">
        <img
          className="first-boot-panel__image"
          src="/images/first-boot.png"
          width={2135}
          height={1277}
          loading="eager"
          fetchPriority="high"
          decoding="async"
          alt="Screenshot of a purple UI TEXT SIZE setup screen with the Small (Default) option visible."
        />
      </div>
      <figcaption className="first-boot-panel__caption">
        <span>Maintainer-supplied first-boot screen</span>
        <span className="first-boot-panel__links">
          <a href="/images/first-boot.png" target="_blank" rel="noopener noreferrer">View full size</a>
          <a href="https://imgur.com/a/S0evCSS" target="_blank" rel="noopener noreferrer">Source</a>
        </span>
      </figcaption>
    </figure>
  );
}
