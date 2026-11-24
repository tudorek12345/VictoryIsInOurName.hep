"use client";

import { useId, useState } from "react";
import "./first-boot-panel.css";

const VIDEO_PATH = "/media/first-boot-loading.mp4";
const VIDEO_SOURCE = "https://streamable.com/0dtjxh";

export default function FirstBootPanel() {
  const titleId = useId();
  const captionId = useId();
  const [videoUnavailable, setVideoUnavailable] = useState(false);

  return (
    <figure className="first-boot-panel retro-window" aria-labelledby={titleId}>
      <div className="first-boot-panel__bar window-bar">
        <h2 id={titleId} className="first-boot-panel__title">First Boot</h2>
        <span className="window-controls" aria-hidden="true"><i /><i /><i /></span>
      </div>
      <div className="first-boot-panel__media-wrap">
        <video
          className="first-boot-panel__video"
          src={VIDEO_PATH}
          poster="/images/first-boot.png"
          width={1276}
          height={720}
          controls
          playsInline
          preload="metadata"
          aria-label="Maintainer-supplied First Boot loading video"
          aria-describedby={captionId}
          onError={() => setVideoUnavailable(true)}
          onLoadedMetadata={() => setVideoUnavailable(false)}
        >
          Your browser does not support this video. <a href={VIDEO_PATH} download="leonida-first-boot-loading.mp4">Download the MP4</a> or <a href={VIDEO_SOURCE} target="_blank" rel="noopener noreferrer">open the Streamable source</a>.
        </video>
      </div>
      {videoUnavailable && (
        <p className="first-boot-panel__fallback" role="status">
          This video could not load. Use Download MP4 or open the Streamable source below.
        </p>
      )}
      <figcaption className="first-boot-panel__caption">
        <span id={captionId}>First Boot loading video</span>
        <span className="first-boot-panel__links">
          <a href={VIDEO_PATH} download="leonida-first-boot-loading.mp4">Download MP4</a>
          <a href={VIDEO_SOURCE} target="_blank" rel="noopener noreferrer">Streamable source</a>
          <a href="/images/first-boot.png" target="_blank" rel="noopener noreferrer">Original screenshot</a>
        </span>
      </figcaption>
    </figure>
  );
}
