"use client";

import { useEffect, useRef, useState } from "react";
import { SHOWCASE_EVENT_URL } from "../lib/progress-update";

export type Resource = { title: string; description: string; href: string; category: string; shortcut?: string };
export const resources: Resource[] = [
  {title:"Discord progress showcase — 25 November",description:"Join the stream, showcases, development and build updates. See your local time in Discord.",href:SHOWCASE_EVENT_URL,category:"EVENT"},
  {title:"Latest reported runtime progress",description:"23 November: one Windows 11 / RX 9070 XT report, working stages and the world-rendering blocker.",href:"#progress-update",category:"UPDATE"},
  {title:"Progress report and Marvis credit",description:"Read the maintainer-supplied stage table and ongoing collaboration note.",href:"/progress-update.md",category:"DOCUMENT"},
  {title:"Developer handoff",description:"The full brief for the next native runtime investigation.",href:"/handoff.md",category:"DOCUMENT"},
  {title:"Experiment workbench",description:"Prepare a local experiment and export a reproducible handoff.",href:"#workbench",category:"LOCAL TOOL"},
  {title:"Fork source",description:"tudorek12345/Leonida on GitHub.",href:"https://github.com/tudorek12345/Leonida",category:"REPOSITORY"},
  {title:"Upstream Leonida",description:"The original project and ongoing community work.",href:"https://github.com/ItsNotRexed/Leonida",category:"UPSTREAM"},
  {title:"Historical upstream boot-chain report",description:"An earlier 23 November 2026 upstream experiment, retained as reference.",href:"https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md",category:"EVIDENCE"},
  {title:"Startup tracing runbook",description:"Loader passes, startup traces, and D3D12 diagnostics.",href:"https://github.com/ItsNotRexed/Leonida/blob/main/docs/boot.md",category:"DOCUMENT"},
  {title:"Fork experiment workflow",description:"Short, reversible experiments with explicit results.",href:"https://github.com/tudorek12345/Leonida/blob/main/docs/FORK_EXPERIMENTS.md",category:"DOCUMENT"},
  {title:"Heperkoo’s Discord",description:"The existing MWCMP development community.",href:"https://discord.gg/ufXqPcVdVj",category:"COMMUNITY"},
];

export default function CommandPalette({open,onClose}:{open:boolean;onClose:()=>void}){
  const [query,setQuery]=useState("");
  const input=useRef<HTMLInputElement>(null);
  const panel=useRef<HTMLDivElement>(null);
  const previousFocus=useRef<HTMLElement|null>(null);
  const results=resources.filter(resource=>`${resource.title} ${resource.description} ${resource.category}`.toLowerCase().includes(query.trim().toLowerCase()));
  useEffect(()=>{
    if(!open)return;
    previousFocus.current=document.activeElement as HTMLElement;
    setQuery("");
    const timer=setTimeout(()=>input.current?.focus(),0);
    const overflow=document.body.style.overflow;
    document.body.style.overflow="hidden";
    const keydown=(event:KeyboardEvent)=>{
      if(event.key==="Escape"){event.preventDefault();onClose();}
      if(event.key==="Tab"){
        const nodes=panel.current?.querySelectorAll<HTMLElement>('input,button,a[href]');
        if(!nodes?.length)return;
        const first=nodes[0];const last=nodes[nodes.length-1];
        if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
        else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
      }
      if(event.key==="ArrowDown"&&document.activeElement===input.current){event.preventDefault();panel.current?.querySelector<HTMLAnchorElement>(".command-result")?.focus();}
    };
    document.addEventListener("keydown",keydown);
    return()=>{clearTimeout(timer);document.body.style.overflow=overflow;document.removeEventListener("keydown",keydown);previousFocus.current?.focus();};
  },[open,onClose]);
  if(!open)return null;
  return <div className="command-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose();}}><div className="command-palette retro-window" ref={panel} role="dialog" aria-modal="true" aria-label="Find a resource"><div className="window-bar"><span>resource-index / quick open</span><button onClick={onClose} aria-label="Close resource search">ESC</button></div><label className="command-input"><span aria-hidden="true">&gt;_</span><input ref={input} value={query} onChange={event=>setQuery(event.target.value)} placeholder="Find a document, source, or tool…" aria-label="Search resources" autoComplete="off"/></label><div className="command-results">{results.map(resource=><a key={resource.href} className="command-result" href={resource.href} target={resource.href.startsWith("http")?"_blank":undefined} rel={resource.href.startsWith("http")?"noopener noreferrer":undefined} onClick={onClose}><span><strong>{resource.title}</strong><span>{resource.description}</span></span><small>{resource.category}</small></a>)}{!results.length&&<p className="command-empty">No resources match “{query}”. Try “boot”, “handoff”, or “Discord”.</p>}</div><div className="command-hint"><span>Tab to navigate · Enter to open</span><span>Ctrl / ⌘ K</span></div></div></div>;
}
