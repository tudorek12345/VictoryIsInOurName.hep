import { PROGRESS_UPDATE, RECENT_RUNTIME_UPDATE } from "../lib/progress-update";
import "./progress-update.css";

export default function ProgressUpdate() {
  const reportDate = new Date(PROGRESS_UPDATE.date);
  const dateLabel = Number.isNaN(reportDate.getTime())
    ? PROGRESS_UPDATE.date
    : new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(reportDate);
  const workingCount = PROGRESS_UPDATE.stages.filter(stage => stage.status === "working").length;
  const stageCount = PROGRESS_UPDATE.stages.length;
  const meterDescription = `${workingCount} of ${stageCount} reported stages working. World entry is reached, but rendering remains blocked. This is a count of reported boot stages, not a gameplay compatibility rating.`;

  return (
    <section className="progress-update section page-width" id="progress-update" aria-labelledby="progress-update-title">
      <div className="progress-update__heading">
        <div>
          <p className="progress-update__eyebrow">USER-REPORTED PROGRESS</p>
          <h2 id="progress-update-title">Runtime updates &amp; reported stages.</h2>
        </div>
      </div>

      <section className="progress-update__next" aria-labelledby="recent-runtime-update-title">
        <div className="progress-update__next-heading">
          <h3 id="recent-runtime-update-title">Latest runtime update</h3>
          <time dateTime={RECENT_RUNTIME_UPDATE.timestamp}>{RECENT_RUNTIME_UPDATE.label}</time>
        </div>
        <p className="progress-update__scope">{RECENT_RUNTIME_UPDATE.environment}. {RECENT_RUNTIME_UPDATE.scope}</p>
        <p className="progress-update__scope">{RECENT_RUNTIME_UPDATE.changes.join(" ")}</p>
        <p className="progress-update__scope">
          {RECENT_RUNTIME_UPDATE.performance.scope} Hardware: {RECENT_RUNTIME_UPDATE.performance.hardware.fps} FPS / {RECENT_RUNTIME_UPDATE.performance.hardware.frameTimeMs} ms;
          {" "}WARP: ~{RECENT_RUNTIME_UPDATE.performance.warp.fps} FPS / ~{RECENT_RUNTIME_UPDATE.performance.warp.frameTimeMs} ms.
        </p>
        <ol aria-label="Recent runtime work checklist">
          {RECENT_RUNTIME_UPDATE.checklist.map(item => (
            <li key={item.id} style={{ gridTemplateColumns: "max-content minmax(0, 1fr)" }}>
              <span aria-hidden="true" style={{ whiteSpace: "pre" }}>{item.status === "completed" ? "[✓]" : "[ ]"}</span>
              <div>
                <h4>{item.title}</h4>
                <span className="progress-update__next-label">{item.status === "completed" ? "Completed" : item.status === "partial" ? "In progress (partial)" : "Pending"}</span>
                <p>{item.detail}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <div className="progress-update__heading">
        <h3>Historical stage report</h3>
        <div className="progress-update__environment">
          <time dateTime={PROGRESS_UPDATE.date}>{dateLabel}</time>
          <span>{PROGRESS_UPDATE.environment}</span>
          <span>Single-machine report</span>
        </div>
      </div>

      <div className="progress-update__window">
        <div className="progress-update__bar"><span>boot-progress.log</span><span>REPORTED IMPLEMENTATION STATUS</span></div>
        <div className="progress-update__meter">
          <div className="progress-update__meter-heading">
            <p><strong>{workingCount}</strong> / {stageCount} stages reported working</p>
            <span>World reached · rendering blocked</span>
          </div>
          <div
            className="progress-update__segments"
            role="progressbar"
            aria-label="Reported boot-stage progress"
            aria-valuemin={0}
            aria-valuemax={stageCount}
            aria-valuenow={workingCount}
            aria-valuetext={meterDescription}
          >
            {PROGRESS_UPDATE.stages.map(stage => (
              <div key={stage.id} className={`progress-update__segment progress-update__segment--${stage.status}`} aria-hidden="true">
                <span className="progress-update__segment-fill" />
                <span className="progress-update__segment-label"><b>{stage.status === "working" ? "✓" : "!"}</b>{stage.shortLabel}</span>
                <span className="progress-update__segment-state">{stage.status === "working" ? "Reported working" : "Rendering blocked"}</span>
              </div>
            ))}
          </div>
          <p className="progress-update__meter-note">A count of the stages in this report — not a compatibility percentage or a claim of playable gameplay.</p>
        </div>

        <table className="progress-update__table">
          <caption className="progress-update__sr-only">Reported implementation status on one machine. These results have not been independently reproduced for this update.</caption>
          <thead><tr><th scope="col">Stage</th><th scope="col">Implementation state</th></tr></thead>
          <tbody>
            {PROGRESS_UPDATE.stages.map(row => (
              <tr key={row.id}>
                <th scope="row"><span className="progress-update__stage">{row.stage}</span><p>{row.detail}</p></th>
                <td>
                  <span className={`progress-update__state${row.status === "blocked" ? " progress-update__state--blocked" : ""}`}>
                    <span aria-hidden="true">{row.status === "working" ? "✓" : "!"}</span>
                    {row.status === "working" ? "Implemented / working — reported" : "World reached / rendering blocked — reported"}
                  </span>
                  <span className="progress-update__result">{row.state}</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="progress-update__limit"><span aria-hidden="true">!</span><p>The reported 30 fps applies to the first-boot screens, <strong>not gameplay</strong>. World entry is reached, but its image remains black and the host GPU fails within seconds. The exact cause is not established.</p></div>
      </div>

      <p className="progress-update__scope">{PROGRESS_UPDATE.scope}</p>
      <div className="progress-update__next">
        <div className="progress-update__next-heading"><h3>Next steps from the 23 November report</h3><span>OPEN WORK · NOT COMPLETED</span></div>
        <ol>
          {PROGRESS_UPDATE.nextSteps.map(step => (
            <li key={step.id}>
              <span className="progress-update__open-mark" aria-hidden="true" />
              <div><h4>{step.title}</h4><p>{step.detail}</p></div>
              <span className="progress-update__next-label">Next</span>
            </li>
          ))}
        </ol>
      </div>
      <p className="progress-update__credit">{PROGRESS_UPDATE.credit}</p>
    </section>
  );
}
