import { PROGRESS_UPDATE } from "../lib/progress-update";
import "./progress-update.css";

export default function ProgressUpdate() {
  const reportDate = new Date(PROGRESS_UPDATE.date);
  const dateLabel = Number.isNaN(reportDate.getTime())
    ? PROGRESS_UPDATE.date
    : new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(reportDate);

  return (
    <section className="progress-update section page-width" id="progress-update" aria-labelledby="progress-update-title">
      <div className="progress-update__heading">
        <div>
          <p className="progress-update__eyebrow">USER-REPORTED PROGRESS</p>
          <h2 id="progress-update-title">The latest boot report.</h2>
        </div>
        <div className="progress-update__environment">
          <time dateTime={PROGRESS_UPDATE.date}>{dateLabel}</time>
          <span>{PROGRESS_UPDATE.environment}</span>
        </div>
      </div>
      <div className="progress-update__window">
        <div className="progress-update__bar"><span>boot-progress.log</span><span>SINGLE-MACHINE REPORT</span></div>
        <table className="progress-update__table">
          <caption className="progress-update__sr-only">Reported boot progress. These results describe one machine and have not been independently reproduced for this update.</caption>
          <thead><tr><th scope="col">Stage</th><th scope="col">State</th></tr></thead>
          <tbody>
            {PROGRESS_UPDATE.stages.map(row => {
              const blocked = /blocked|fail|black|reached|partial/i.test(row.state);
              return (
                <tr key={row.id}>
                  <th scope="row"><span className="progress-update__stage">{row.stage}</span><p>{row.detail}</p></th>
                  <td><span className={`progress-update__state${blocked ? " progress-update__state--blocked" : ""}`}>{row.state}</span></td>
                </tr>
              );
            })}
          </tbody>
        </table>
        <div className="progress-update__limit"><span aria-hidden="true">!</span><p>The reported 30 fps applies to the first-boot screens, <strong>not gameplay</strong>. World entry is reached, but its image remains black and the host GPU fails within seconds. The exact cause is not established.</p></div>
      </div>
      <p className="progress-update__scope">{PROGRESS_UPDATE.scope}</p>
      <p className="progress-update__credit">{PROGRESS_UPDATE.credit}</p>
    </section>
  );
}
