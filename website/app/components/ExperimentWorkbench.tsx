"use client";

import { useEffect, useId, useMemo, useState } from "react";
import {
  createEmptyDraft,
  FIELD_LIMITS,
  getReadiness,
  isBaselineSha,
  parseStoredDraft,
  serializeDraft,
  toHandoffMarkdown,
  WORKBENCH_PRESETS,
  WORKBENCH_STORAGE_KEY,
  type DraftTextField,
  type ExperimentDraft,
  type InvestigationId,
} from "../lib/workbench";
import "./workbench.css";

function WorkbenchIcon({ name }: { name: "copy" | "download" | "undo" }) {
  return <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {name === "copy" && <><rect x="8" y="8" width="12" height="13" rx="1"/><path d="M16 8V3H3v13h5"/></>}
    {name === "download" && <><path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/></>}
    {name === "undo" && <><path d="M9 4 4 9l5 5M4 9h10a6 6 0 0 1 0 12"/></>}
  </svg>;
}

export default function ExperimentWorkbench() {
  const prefix = useId();
  const [draft, setDraft] = useState<ExperimentDraft>(() => createEmptyDraft());
  const [restored, setRestored] = useState(false);
  const [storage, setStorage] = useState<"loading" | "saved" | "session">("loading");
  const [undoDraft, setUndoDraft] = useState<ExperimentDraft | null>(null);
  const [feedback, setFeedback] = useState("");
  const [copying, setCopying] = useState(false);

  useEffect(() => {
    // Read after hydration; a saved browser draft must not change the server markup.
    const timer = window.setTimeout(() => {
      try {
        const saved = parseStoredDraft(window.localStorage.getItem(WORKBENCH_STORAGE_KEY));
        if (saved) setDraft(saved);
      } catch {
        setStorage("session");
      }
      setRestored(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!restored) return;
    const timer = window.setTimeout(() => {
      try {
        window.localStorage.setItem(WORKBENCH_STORAGE_KEY, serializeDraft(draft));
        setStorage("saved");
      } catch {
        setStorage("session");
      }
    }, 200);
    return () => window.clearTimeout(timer);
  }, [draft, restored]);

  const preset = WORKBENCH_PRESETS.find(item => item.id === draft.investigation) ?? WORKBENCH_PRESETS[0];
  const readiness = getReadiness(draft);
  const completed = readiness.filter(item => item.complete).length;
  const markdown = useMemo(() => toHandoffMarkdown(draft), [draft]);
  const hasNotes = Object.keys(FIELD_LIMITS).some(field => Boolean(draft[field as DraftTextField])) || draft.resultChecked;
  const invalidBaseline = Boolean(draft.baseline.trim()) && !isBaselineSha(draft.baseline);

  function update(field: DraftTextField, value: string) {
    setDraft(current => ({ ...current, [field]: value.slice(0, FIELD_LIMITS[field]), resultChecked: field === "nextStep" ? current.resultChecked : false }));
    setUndoDraft(null);
    setFeedback("");
  }

  function selectInvestigation(investigation: InvestigationId) {
    setDraft(current => ({ ...current, investigation, resultChecked: current.investigation === investigation ? current.resultChecked : false }));
    setUndoDraft(null);
    setFeedback("");
  }

  async function copyHandoff() {
    setCopying(true);
    try {
      await navigator.clipboard.writeText(markdown);
      setFeedback("Copied the Markdown handoff.");
    } catch {
      setFeedback("Clipboard unavailable. Download the file or select the preview text to copy it.");
    } finally {
      setCopying(false);
    }
  }

  function downloadHandoff() {
    try {
      const url = URL.createObjectURL(new Blob([markdown], { type: "text/markdown;charset=utf-8" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `leonida-${draft.investigation}-handoff.md`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      setFeedback("Markdown download requested. Check your browser’s downloads.");
    } catch {
      setFeedback("Download unavailable. Copy the handoff or select the preview text.");
    }
  }

  function resetDraft() {
    setUndoDraft({ ...draft });
    setDraft(createEmptyDraft(draft.investigation));
    setFeedback("Notes cleared. Undo is available until your next edit.");
  }

  function undoReset() {
    if (!undoDraft) return;
    setDraft(undoDraft);
    setUndoDraft(null);
    setFeedback("Previous draft restored.");
  }

  return <section id="workbench" className="experiment-workbench" aria-labelledby={`${prefix}-heading`}>
    <div className="ew-inner">
      <div className="ew-heading-row">
        <div>
          <p className="ew-eyebrow"><span aria-hidden="true">&gt;_</span> EXPERIMENT WORKBENCH</p>
          <h2 id={`${prefix}-heading`}>Make the next run count.</h2>
          <p className="ew-intro">One hypothesis. One reproducible experiment. A handoff the next developer can use.</p>
        </div>
        <span className="ew-local-badge"><span aria-hidden="true"/>LOCAL DRAFT</span>
      </div>

      <div className="ew-focus" role="group" aria-label="Investigation focus">
        {WORKBENCH_PRESETS.map(item => <button key={item.id} type="button" aria-pressed={draft.investigation === item.id} disabled={!restored} className={`ew-preset ${draft.investigation === item.id ? "is-selected" : ""}`} onClick={() => selectInvestigation(item.id)}>
          <span className="ew-preset-index">{item.short}</span>
          <span className="ew-preset-title">{item.title}<span className="ew-preset-marker" aria-hidden="true"/></span>
        </button>)}
      </div>
      <p className="ew-focus-note"><span>{preset.description}</span> Switching focus keeps your notes.</p>

      <div className="ew-grid">
        <fieldset className="ew-fields" disabled={!restored}>
          <legend className="ew-sr-only">Experiment details</legend>
          <div className="ew-field">
            <label htmlFor={`${prefix}-hypothesis`}>Hypothesis <span>01</span></label>
            <textarea id={`${prefix}-hypothesis`} rows={3} value={draft.hypothesis} onChange={event => update("hypothesis", event.target.value)} maxLength={FIELD_LIMITS.hypothesis} placeholder={preset.hypothesis}/>
          </div>

          <div className="ew-field-pair ew-context">
            <div className="ew-field">
              <label htmlFor={`${prefix}-baseline`}>Baseline commit</label>
              <input id={`${prefix}-baseline`} type="text" autoComplete="off" autoCapitalize="none" spellCheck={false} value={draft.baseline} maxLength={FIELD_LIMITS.baseline} placeholder="Commit SHA" aria-invalid={invalidBaseline} aria-describedby={`${prefix}-baseline-help`} onChange={event => update("baseline", event.target.value)}/>
              <span className={`ew-field-help ${invalidBaseline ? "ew-invalid" : ""}`} id={`${prefix}-baseline-help`}>{invalidBaseline ? "Use a 7–40 character hexadecimal commit SHA." : "Record the exact tested revision."}</span>
            </div>
            <div className="ew-field">
              <label htmlFor={`${prefix}-environment`}>Environment / GPU / driver</label>
              <input id={`${prefix}-environment`} type="text" autoComplete="off" value={draft.environment} maxLength={FIELD_LIMITS.environment} placeholder="OS, GPU and driver version" onChange={event => update("environment", event.target.value)}/>
            </div>
          </div>

          <div className="ew-field">
            <label htmlFor={`${prefix}-command`}>Reproduction command <span>02</span></label>
            <textarea id={`${prefix}-command`} className="ew-command" rows={3} value={draft.command} onChange={event => update("command", event.target.value)} maxLength={FIELD_LIMITS.command} autoCapitalize="none" spellCheck={false} placeholder={preset.command}/>
            <span className="ew-field-help">Record your command here. This page does not execute it.</span>
          </div>

          <div className="ew-field-pair">
            <div className="ew-field">
              <label htmlFor={`${prefix}-expected`}>Expected outcome <span>03</span></label>
              <textarea id={`${prefix}-expected`} rows={4} value={draft.expected} onChange={event => update("expected", event.target.value)} maxLength={FIELD_LIMITS.expected} placeholder={preset.expected}/>
            </div>
            <div className="ew-field">
              <label htmlFor={`${prefix}-observed`}>Observed outcome <span>04</span></label>
              <textarea id={`${prefix}-observed`} rows={4} value={draft.observed} onChange={event => update("observed", event.target.value)} maxLength={FIELD_LIMITS.observed} placeholder="Not run yet? Leave this empty. Otherwise record the result and local evidence path."/>
            </div>
          </div>

          <label className="ew-confirm" htmlFor={`${prefix}-checked`}>
            <input id={`${prefix}-checked`} type="checkbox" checked={draft.resultChecked} disabled={!draft.observed.trim()} onChange={event => { setDraft(current => ({ ...current, resultChecked: event.target.checked })); setUndoDraft(null); setFeedback(""); }}/>
            <span>I checked this observed result against my local evidence.</span>
          </label>

          <div className="ew-field">
            <label htmlFor={`${prefix}-next`}>Next step / handoff <span>05</span></label>
            <textarea id={`${prefix}-next`} rows={2} value={draft.nextStep} onChange={event => update("nextStep", event.target.value)} maxLength={FIELD_LIMITS.nextStep} placeholder="What should the next developer measure or change?"/>
          </div>

          <div className="ew-draft-actions">
            <span className="ew-storage">{storage === "loading" ? "Restoring local draft…" : storage === "saved" ? "Autosaved in this browser" : "Session only — download to keep your notes"}</span>
            <div>
              {undoDraft && <button type="button" className="ew-quiet-button" onClick={undoReset}><WorkbenchIcon name="undo"/>Undo</button>}
              <button type="button" className="ew-quiet-button" disabled={!hasNotes} onClick={resetDraft}>Reset notes</button>
            </div>
          </div>
        </fieldset>

        <aside className="ew-output" aria-label="Local preparation and handoff preview">
          <div className="ew-terminal-title"><span><span className="ew-terminal-symbol" aria-hidden="true">&gt;_</span> handoff.md</span><span>LIVE PREVIEW</span></div>
          <div className="ew-readiness">
            <div className="ew-progress-label"><span>LOCAL PREPARATION</span><strong>{completed}<span> / {readiness.length}</span></strong></div>
            <div className="ew-progress" role="progressbar" aria-label="Local experiment preparation" aria-valuemin={0} aria-valuemax={readiness.length} aria-valuenow={completed} aria-valuetext={`${completed} of ${readiness.length} preparation steps complete. This does not measure game compatibility.`}>
              {Array.from({ length: 20 }, (_, index) => <span key={index} className={index < completed * 4 ? "is-filled" : ""} aria-hidden="true"/>)}
            </div>
            <p className="ew-progress-note">Readiness of this note, not game compatibility.</p>
            <ul className="ew-checklist">
              {readiness.map(item => <li key={item.id} className={item.complete ? "is-complete" : ""}><span className="ew-check-symbol" aria-hidden="true">{item.complete ? "[x]" : "[ ]"}</span><span className="ew-sr-only">{item.complete ? "Complete: " : "Incomplete: "}</span>{item.label}</li>)}
            </ul>
          </div>
          <div className="ew-preview-label"><span>MARKDOWN / EXPORT</span><span>{draft.observed.trim() ? "AUTHOR-ENTERED NOTES" : "NO RESULT RECORDED"}</span></div>
          <pre className="ew-preview" tabIndex={0} aria-label="Generated Markdown handoff">{markdown}</pre>
          <div className="ew-export-actions">
            <button type="button" className="ew-button ew-button-primary" disabled={!restored || copying} onClick={() => void copyHandoff()}><WorkbenchIcon name="copy"/>{copying ? "Copying…" : "Copy handoff"}</button>
            <button type="button" className="ew-button" disabled={!restored} onClick={downloadHandoff}><WorkbenchIcon name="download"/>Download .md</button>
          </div>
          <div className="ew-feedback" role="status" aria-live="polite">{feedback}</div>
        </aside>
      </div>
      <p className="ew-disclosure"><span aria-hidden="true">↳</span> Browser-local notes. Nothing is sent to GitHub or published automatically. Review your export before sharing it.</p>
    </div>
  </section>;
}
