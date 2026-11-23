"use client";

import { useCallback, useEffect, useState } from "react";
import { PROJECT_SNAPSHOT, type ProjectData } from "./lib/project-data";
import FirstBootPanel from "./components/FirstBootPanel";
import CommandPalette, { resources } from "./components/CommandPalette";
import VisitorCounter from "./components/VisitorCounter";
import ExperimentWorkbench from "./components/ExperimentWorkbench";
import ChristmasBanner from "./components/ChristmasBanner";
import ShowcaseCountdown from "./components/ShowcaseCountdown";

const REPO="https://github.com/tudorek12345/Leonida";
const UPSTREAM="https://github.com/ItsNotRexed/Leonida";
const REPORT="https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md";
const DISCORD="https://discord.gg/ufXqPcVdVj";
const TORRENT_LINKS="https://justpaste.it/ik5xi";
const CLONE="git clone --recursive https://github.com/tudorek12345/Leonida.git";
type Palette="phosphor"|"amber";

const checkpoints=[
  {name:"Executable startup",state:"reported",label:"REPORTED",detail:"Early runtime execution",symbol:"✓"},
  {name:"Graphics setup",state:"reported",label:"REPORTED",detail:"Device, queues & lists",symbol:"✓"},
  {name:"Descriptor heap",state:"checkpoint",label:"REFERENCE STOP",detail:"CPU-handle assertion",symbol:"!"},
  {name:"Draw & present",state:"unknown",label:"UNVERIFIED",detail:"No frame in cited report",symbol:"·"},
  {name:"Playable session",state:"unknown",label:"UNVERIFIED",detail:"A later milestone",symbol:"·"},
];
const lanes=[
  {tag:"RUNTIME",title:"Follow the first failing call.",description:"Reconcile upstream fixes, reproduce the current checkout, then investigate loader, TLS, storage, and XMem behavior.",path:"runtime / loader + shims",href:`${UPSTREAM}/blob/main/docs/boot.md`},
  {tag:"GRAPHICS",title:"Make memory mean the same thing.",description:"Measure Xbox ABI and descriptor expectations. Connect the game's CPU writes to the resources the Vulkan backend actually sees.",path:"graphics / ABI + memory",href:REPORT},
  {tag:"HANDOFF",title:"Leave the next step executable.",description:"Record the revision, environment, hypothesis, commands, and observed result. Share sanitized findings and keep game traces local.",path:"workflow / reproduce + record",href:"/handoff.md"},
];
function dateLabel(value:string){const date=new Date(value);return Number.isNaN(date.getTime())?"Date unavailable":new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"numeric",timeZone:"UTC"}).format(date);}

export default function Home(){
  const [palette,setPalette]=useState<Palette>("phosphor");
  const [crt,setCrt]=useState(false);
  const [preferencesLoaded,setPreferencesLoaded]=useState(false);
  const [menuOpen,setMenuOpen]=useState(false);
  const [commandOpen,setCommandOpen]=useState(false);
  const [copied,setCopied]=useState(false);
  const [copyError,setCopyError]=useState(false);
  const [query,setQuery]=useState("");
  const [project,setProject]=useState<ProjectData>(PROJECT_SNAPSHOT);
  const [loading,setLoading]=useState(true);
  const [activityMessage,setActivityMessage]=useState("Checking the public repository…");
  const closeCommand=useCallback(()=>setCommandOpen(false),[]);

  useEffect(()=>{
    try{const stored=JSON.parse(localStorage.getItem("leonida:display:v1")||"null");if(stored?.palette==="amber"||stored?.palette==="phosphor")setPalette(stored.palette);if(typeof stored?.crt==="boolean")setCrt(stored.crt);}catch{/* Display preferences are optional. */}
    setPreferencesLoaded(true);
  },[]);
  useEffect(()=>{if(preferencesLoaded)try{localStorage.setItem("leonida:display:v1",JSON.stringify({palette,crt}));}catch{/* The controls still work without persistence. */}},[palette,crt,preferencesLoaded]);
  useEffect(()=>{const keydown=(event:KeyboardEvent)=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==="k"){event.preventDefault();setCommandOpen(value=>!value);}};window.addEventListener("keydown",keydown);return()=>window.removeEventListener("keydown",keydown);},[]);

  const loadProject=useCallback(async(signal?:AbortSignal)=>{
    setLoading(true);
    try{const response=await fetch("/api/project",{signal,headers:{Accept:"application/json"}});if(!response.ok)throw new Error("Unavailable");const data=await response.json() as ProjectData;if(!data.repo||!Array.isArray(data.commits))throw new Error("Incomplete");setProject(data);setActivityMessage(data.source==="github"?"Public GitHub response. Cached briefly by the backend.":(data.notice||"Showing a checked repository snapshot."));}
    catch(error){if(error instanceof Error&&error.name==="AbortError")return;setProject(PROJECT_SNAPSHOT);setActivityMessage("Live activity is unavailable. Showing the checked repository snapshot.");}
    finally{if(!signal?.aborted)setLoading(false);}
  },[]);
  useEffect(()=>{const controller=new AbortController();void loadProject(controller.signal);return()=>controller.abort();},[loadProject]);
  useEffect(()=>{if(!copied)return;const timer=setTimeout(()=>setCopied(false),2500);return()=>clearTimeout(timer);},[copied]);
  const copyClone=async()=>{try{await navigator.clipboard.writeText(CLONE);setCopied(true);setCopyError(false);}catch{setCopyError(true);}};
  const filteredResources=resources.filter(item=>`${item.title} ${item.description} ${item.category}`.toLowerCase().includes(query.toLowerCase().trim()));

  return <div className={`site-shell palette-${palette} ${crt?"crt-enabled":""}`}>
    <a className="skip-link" href="#main">Skip to content</a>
    <div className="system-bar"><div><span className="system-square" aria-hidden="true"/> HEPERKOO’S DEVELOPMENT DESKTOP</div><span>INDEPENDENT RESEARCH · PUBLIC SOURCE</span></div>
    <header className="site-header page-width">
      <a className="wordmark" href="#" aria-label="Leonida home"><span className="pixel-logo" aria-hidden="true">L</span><span>LEONIDA<span className="wordmark-sub">EXPERIMENTAL FORK / HK</span></span></a>
      <nav className={`main-nav ${menuOpen?"is-open":""}`} aria-label="Main navigation">
        <a href="#project" onClick={()=>setMenuOpen(false)}>Read me</a><a href="#workbench" onClick={()=>setMenuOpen(false)}>Workbench</a><a href="#activity" onClick={()=>setMenuOpen(false)}>Git log</a>
        <button className="search-launcher" onClick={()=>{setCommandOpen(true);setMenuOpen(false);}} aria-label="Open resource search, Control or Command K"><span>Find a file</span><kbd>⌘ K</kbd></button>
      </nav>
      <button className="mobile-menu" aria-expanded={menuOpen} aria-label={menuOpen?"Close navigation":"Open navigation"} onClick={()=>setMenuOpen(value=>!value)}>{menuOpen?"CLOSE":"MENU"}</button>
    </header>
    <ChristmasBanner/>
    <ShowcaseCountdown/>
    <main id="main">
      <section className="hero page-width">
        <div className="desktop-path"><span>~/projects/leonida</span><span className="display-controls"><button onClick={()=>setPalette(value=>value==="phosphor"?"amber":"phosphor")} aria-label={`Color palette: ${palette}. Switch palette.`}><span className="palette-swatch" aria-hidden="true"/>{palette==="phosphor"?"Phosphor":"Amber"}</button><button className={crt?"selected":""} aria-pressed={crt} onClick={()=>setCrt(value=>!value)}>CRT {crt?"ON":"OFF"}</button></span></div>
        <div className="hero-actions">
          <a className="button button-primary" href={TORRENT_LINKS} target="_blank" rel="noopener noreferrer" title="Open GTA torrent links on JustPaste.it in a new tab">GTA torrent links</a>
        </div>
        <div className="hero-grid">
          <div className="hero-copy"><div className="overline"><span className="bracket">[</span> NATIVE PC RUNTIME RESEARCH <span className="bracket">]</span></div><h1>A native future.<br/>One <span>real frame.</span><span className="text-cursor" aria-hidden="true">_</span></h1><p>Working toward <strong>GTA VI running natively on PC</strong> through Leonida. Real experiments, clear evidence, and a handoff the next developer can actually use.</p><div className="hero-actions"><a className="button button-primary" href={REPO} target="_blank" rel="noopener noreferrer"><span aria-hidden="true">&lt;/&gt;</span> Open the fork</a><a className="button button-secondary" href={DISCORD} target="_blank" rel="noopener noreferrer">Join my Discord</a></div><p className="honest-status"><span className="warning-square" aria-hidden="true">!</span> Experimental. No verified rendered gameplay in this fork.</p><div className="hero-credit">Built on <a href={UPSTREAM} target="_blank" rel="noopener noreferrer">ItsNotRexed / Leonida</a> and its contributors.</div></div>
          <FirstBootPanel/>
        </div>
        <div className="hero-bottom"><div className="desktop-note"><span className="note-label">THE OBJECTIVE</span><p>Get the real game to generate a frame.<br/><span>Then prove that someone else can reproduce it.</span></p></div><VisitorCounter className="terminal-counter"/></div>
      </section>

      <section id="project" className="section page-width project-section"><div className="section-heading"><div><p className="overline">README.MD</p><h2>A fork for the work<br/><span>between the milestones.</span></h2></div><p>Not a download of GTA VI. A working space for runtime investigation, integration, testing, and collaboration.</p></div><div className="project-grid"><div className="project-description"><p>I’m <strong>Heperkoo</strong>. I’m bringing my ongoing modding and porting workflow to Leonida: inspect a behavior, implement a focused change, test it, then document what actually happened.</p><p>The project’s approach runs the game’s existing <strong>x86-64 CPU code</strong> on the PC, reimplements required console services, and translates console GPU programs for Vulkan. The runtime and compatibility work are the hard part.</p><a className="inline-link" href="/handoff.md" download>Download the developer handoff</a></div><div className="architecture-panel retro-window"><div className="window-bar"><span>runtime-map.txt</span><span>REFERENCE ARCHITECTURE</span></div><dl><div><dt>CPU EXECUTION</dt><dd>x86-64 game code</dd><span>Native instructions</span></div><div><dt>SYSTEM LAYER</dt><dd>Console services</dd><span>Loader · TLS · GDK · XMem</span></div><div><dt>GRAPHICS CONTRACT</dt><dd>Xbox D3D12</dd><span>ABI · descriptors · resources</span></div><div><dt>PC BACKEND</dt><dd>Vulkan</dd><span>SPIR-V · submit · present</span></div></dl></div></div></section>

      <section id="checkpoint" className="section page-width checkpoint-section"><div className="section-heading"><div><p className="overline">DOCUMENTED CHECKPOINT</p><h2>Read the trace.<br/><span>Keep the claims honest.</span></h2></div><a className="button button-secondary" href={REPORT} target="_blank" rel="noopener noreferrer">Read the source report</a></div><div className="boot-terminal retro-window"><div className="window-bar"><span><span className="window-icon" aria-hidden="true"/> boot-reference.log</span><span>23 NOV 2026 / PINNED UPSTREAM REPORT</span></div><div className="terminal-intro"><span className="prompt-marker" aria-hidden="true">&gt;</span><p>trace.inspect <span>--source upstream --scope recorded-experiment</span></p></div><div className="boot-strip" aria-label="Documented upstream boot stages, not a completion percentage">{checkpoints.map(item=><div key={item.name} className={`boot-stage stage-${item.state}`}><span className="boot-stage-bar" aria-hidden="true">{item.state==="reported"?"████████":item.state==="checkpoint"?"▓▓▓▓░░░░":"░░░░░░░░"}</span><span className="boot-stage-state"><b aria-hidden="true">{item.symbol}</b>{item.label}</span><h3>{item.name}</h3><p>{item.detail}</p></div>)}</div><div className="terminal-result"><span className="tag tag-amber">REFERENCE STOP</span><p>The cited run stopped on a descriptor-heap CPU-handle assertion. It reached no draw or presentation. <strong>Later upstream branches may be further along.</strong></p></div><div className="terminal-footnote"><span>Windows 11 / RTX 4090 / locally combined fixes</span><span>This is not a compatibility percentage.</span></div></div><p className="source-note">A reported upstream observation, not a run independently reproduced by this fork. GitHub activity updates below do not automatically update this curated assessment.</p></section>

      <section id="work" className="section page-width work-section"><div className="section-heading"><div><p className="overline">THE WORK QUEUE</p><h2>Move the next blocker.</h2></div><p>Start with the current checkout and upstream work. A small measured result beats a large assumption.</p></div><div className="work-lanes">{lanes.map(lane=><article className="work-lane" key={lane.tag}><div className="lane-topline"><span className="tag">{lane.tag}</span><span className="lane-dot" aria-hidden="true"/></div><h3>{lane.title}</h3><p>{lane.description}</p><div className="lane-bottom"><code>{lane.path}</code><a href={lane.href} target={lane.href.startsWith("http")?"_blank":undefined} rel={lane.href.startsWith("http")?"noopener noreferrer":undefined}>Open context</a></div></article>)}</div></section>

      <div className="workbench-wrap page-width"><ExperimentWorkbench/></div>

      <section id="activity" className="section page-width activity-section"><div className="section-heading"><div><p className="overline">GIT LOG</p><h2>Work leaves a trace.</h2></div><button className="button button-secondary" onClick={()=>void loadProject()} disabled={loading}>{loading?"Checking GitHub…":"Refresh activity"}</button></div><div className="activity-window retro-window"><div className="window-bar"><span>tudorek12345 / Leonida</span><span className={project.source==="github"?"source-live":"source-snapshot"}>{loading?"CHECKING":project.source==="github"?"GITHUB RESPONSE":"SAVED SNAPSHOT"}</span></div><div className="activity-message" role="status" aria-live="polite"><span className="prompt-marker" aria-hidden="true">&gt;</span>{activityMessage}</div><div className="commit-list">{project.commits.slice(0,5).map(commit=><a href={commit.url} key={commit.sha} className="commit-row" target="_blank" rel="noopener noreferrer"><span className="commit-node" aria-hidden="true"/><code>{commit.sha.slice(0,7)}</code><div><h3>{commit.message.split("\n")[0]}</h3><p>{commit.author} <span aria-hidden="true">/</span> {dateLabel(commit.date)}</p></div><span className="commit-type">COMMIT</span></a>)}{!project.commits.length&&<p className="empty-state">No commits returned. Open the repository history to inspect the source.</p>}</div><div className="activity-footer"><span>Includes inherited upstream work. Commits do not prove gameplay.</span><a href={`${REPO}/commits/main`} target="_blank" rel="noopener noreferrer">Open full history</a></div></div></section>

      <section id="resources" className="section page-width resources-section"><div className="section-heading"><div><p className="overline">RESOURCE INDEX</p><h2>Everything for the next pass.</h2></div><label className="resource-search"><span aria-hidden="true">&gt;_</span><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Filter files & links" aria-label="Filter resources"/></label></div><div className="resource-grid">{filteredResources.map(resource=><a className="resource-card" key={resource.href} href={resource.href} target={resource.href.startsWith("http")?"_blank":undefined} rel={resource.href.startsWith("http")?"noopener noreferrer":undefined}><span className="resource-category">{resource.category}</span><h3>{resource.title}</h3><p>{resource.description}</p></a>)}{!filteredResources.length&&<p className="empty-state">No matching resources. Try “runtime”, “handoff”, or “Discord”.</p>}</div><div className="resource-tip">Prefer the keyboard? <button onClick={()=>setCommandOpen(true)}>Open quick search</button> with <kbd>Ctrl / ⌘ K</kbd>.</div></section>

      <section id="maintainer" className="section page-width maintainer-section"><div className="maintainer-grid"><div className="maintainer-title"><p className="overline">MAINTAINER.PROFILE</p><div className="maintainer-avatar" aria-hidden="true"><span>HK</span><i>_</i></div><h2>Heperkoo</h2><a href="https://github.com/tudorek12345" target="_blank" rel="noopener noreferrer">@tudorek12345</a><span className="maintainer-tool">VS Code + Codex</span></div><div className="maintainer-copy"><h3>Built from ongoing work.</h3><p>I build multiplayer mods, investigate native engines, and work on game porting experiments. AI helps with analysis and implementation. Tested behavior determines what counts as progress.</p><div className="project-history"><div><span>MWCMP</span><p>Multiplayer synchronization, runtime integration, and debugging interactions across players.</p></div><div><span>Batman Telltale port</span><p>Godot porting, scene and asset integration, rendering, and visual iteration.</p></div><a href="https://github.com/tudorek12345/CoD2SP-CO-OP" target="_blank" rel="noopener noreferrer"><span>CoD2 co-op</span><p>Native engine integration, calling conventions, and host-authoritative multiplayer.</p></a><a href="https://github.com/tudorek12345/decomptwdgame1season" target="_blank" rel="noopener noreferrer"><span>TWD source recovery</span><p>C++ reconstruction, hybrid execution experiments, and differential testing.</p></a></div></div></div></section>

      <section id="collaborate" className="collaborate-section"><div className="page-width collaborate-grid"><div><p className="overline">OPEN A NEW SESSION</p><h2>Bring a trace.<br/><span>Let’s move it forward.</span></h2><p>C++, Windows internals, graphics, memory, tooling, or careful testing — useful collaboration starts with a question we can reproduce.</p><div className="collaborate-actions"><a href={DISCORD} className="button button-primary" target="_blank" rel="noopener noreferrer">Join my Discord</a><a href={`${REPO}/pulls`} className="button button-secondary" target="_blank" rel="noopener noreferrer">Contribute on GitHub</a></div><p className="community-note">My existing MWCMP development community. No official Rockstar affiliation.</p></div><div className="clone-terminal retro-window"><div className="window-bar"><span>start-here.sh</span><span>PUBLIC SOURCE</span></div><div className="clone-body"><p><span className="prompt-marker">$</span> <code>{CLONE}</code></p><button className="copy-button" onClick={copyClone}>{copied?"[✓] Copied":"[+] Copy command"}</button>{copyError&&<p className="copy-feedback" role="status">Clipboard unavailable. Select and copy the command above.</p>}<div className="clone-note">Read the handoff. Check upstream coordination. Keep game data and raw traces local.</div><a className="inline-link" href="/handoff.md" download>Get the developer handoff</a></div></div></div></section>
    </main>
    <footer className="page-width site-footer"><div className="footer-top"><a className="wordmark" href="#"><span className="pixel-logo" aria-hidden="true">L</span><span>LEONIDA<span className="wordmark-sub">EXPERIMENTAL FORK / HK</span></span></a><div><a href={UPSTREAM} target="_blank" rel="noopener noreferrer">Original Leonida</a><a href={`${REPO}/blob/main/LICENSE`} target="_blank" rel="noopener noreferrer">GPL-3.0</a><button onClick={()=>setCommandOpen(true)}>Quick search</button></div></div><div className="footer-bottom"><p>Independent community research. Not affiliated with Rockstar Games, Take-Two Interactive, or Microsoft. Project names belong to their respective owners.</p><span>Keep the next handoff useful.</span></div></footer>
    <CommandPalette open={commandOpen} onClose={closeCommand}/>
  </div>;
}
