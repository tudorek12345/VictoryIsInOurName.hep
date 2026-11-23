"use client";

import { useEffect, useRef, useState } from "react";

type Props = { palette: "phosphor" | "amber" };

/** Original procedural illustration. It does not render or execute any game content. */
export default function PixelSandbox({ palette }: Props) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const elapsed = useRef(0);
  const destination = useRef(0);
  const signalTime = useRef(-100);
  const [paused, setPaused] = useState(false);
  const [signal, setSignal] = useState(0);
  const [reset, setReset] = useState(0);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (query.matches) setPaused(true);
    const listener = (event: MediaQueryListEvent) => { if (event.matches) setPaused(true); };
    query.addEventListener("change", listener);
    return () => query.removeEventListener("change", listener);
  }, []);

  useEffect(() => {
    const element = canvas.current;
    const context = element?.getContext("2d");
    if (!element || !context) return;
    const ctx = context;
    let previous = performance.now();
    let frame = 0;
    const accent = palette === "amber" ? "#ffce75" : "#e4d581";
    const dimAccent = palette === "amber" ? "#9d6e3e" : "#587b4a";
    const rect = (x: number, y: number, w: number, h: number, color: string) => { ctx.fillStyle = color; ctx.fillRect(Math.round(x), Math.round(y), w, h); };
    const print = (text: string, x: number, y: number, color: string, size = 7) => { ctx.fillStyle = color; ctx.font = `${size}px monospace`; ctx.fillText(text, Math.round(x), Math.round(y)); };
    const palm = (x: number, y: number, height: number, flip = false) => {
      const side = flip ? -1 : 1;
      for (let i = 0; i < height; i += 5) rect(x + Math.floor(i / 18) * side, y - i, 4, 5, "#3f5054");
      const topX = x + Math.floor(height / 18) * side;
      const topY = y - height;
      [[-25, 7, 12], [-17, 0, 16], [-4, -5, 12], [8, 0, 15], [20, 7, 10]].forEach(([dx,dy,w]) => {rect(topX+dx,topY+dy,w,4,"#6b8575");rect(topX+dx,topY+dy+4,5,4,"#435b58");});
    };
    const draw = (now: number) => {
      const delta = Math.min((now - previous) / 1000, .05);
      previous = now;
      if (!paused) elapsed.current += delta;
      const time = elapsed.current;
      ctx.imageSmoothingEnabled = false;
      rect(0,0,384,224,"#17232b");
      rect(0,0,384,90,"#1d2833");
      for (let i=0;i<36;i++) { const x=(i*73+17)%384; const y=(i*29+11)%100; rect(x,y,1,(i%7===0)?2:1,i%3===0?"#81958f":"#4b6367"); }
      // Scanlined sunset and a distant city, deliberately illustrative.
      for(let line=0;line<49;line+=3){const y=line-24;const half=Math.sqrt(Math.max(0,24*24-y*y));rect(283-half,34+line,half*2,2,line>30?"#b07b75":"#c3a08a");}
      [[0,94,24,35],[28,84,18,45],[47,100,14,29],[64,76,26,53],[94,97,14,32],[113,88,22,41],[140,103,25,26],[176,91,18,38],[203,95,29,34],[238,83,17,46],[260,104,28,25],[296,90,25,39],[327,102,19,27],[354,78,25,51]].forEach(([x,y,w,h],index)=>{rect(x,y,w,h,index%2?"#293b44":"#24373f");for(let wy=y+5;wy<122;wy+=7)for(let wx=x+4;wx<x+w-2;wx+=6)if((wx+wy)%3)rect(wx,wy,2,2,"#65777a");});
      rect(0,127,384,97,"#15232a");
      for(let y=132;y<224;y+=13)rect(0,y,384,1,"#2a3c42");
      for(let x=-200;x<600;x+=30){ctx.strokeStyle="#2a3c42";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(192+(x-192)*.12,128);ctx.lineTo(x,224);ctx.stroke();}
      rect(0,128,384,2,"#53675e");
      // Tiny grassy tile islands soften the hardware scene into a virtual-life garden.
      for(let row=0;row<3;row++)for(let col=0;col<8;col++){const px=115+col*18-row*4;const py=165+row*11;rect(px,py,18,9,(row+col)%2?"#486249":"#526d4a");rect(px+2,py,14,1,"#75905a");}
      [[123,169],[245,184],[151,191],[227,172]].forEach(([x,y])=>{rect(x,y,2,5,"#7b9c60");rect(x-1,y-2,4,3,"#e2bf7a");});
      palm(28,145,52);palm(350,149,70,true);
      // Two hardware stations, and an original tiny courier creature.
      rect(61,135,45,36,"#101a21");rect(59,133,45,34,"#6d817b");rect(62,136,39,28,"#253a3e");rect(66,140,31,19,"#17282b");rect(80,167,5,7,"#74847b");rect(71,174,24,3,"#53645f");
      print("CPU",73,153,accent,8);rect(67,143,12,1,dimAccent);rect(67,156,23,1,dimAccent);
      rect(269,129,52,42,"#101a21");rect(267,127,52,40,"#8b8a7a");rect(271,131,44,30,"#283a3c");rect(274,134,38,24,"#14272b");rect(289,167,8,7,"#829083");rect(279,174,28,3,"#566b64");print("FRAME?",276,148,"#90c2bf",8);rect(277,153,28,1,"#4b7171");
      const travel = destination.current === 0 ? Math.sin(time*.55)*30 : destination.current === 1 ? -48 : 48;
      const x = 181 + travel;
      const bob = paused?0:Math.round(Math.sin(time*3));
      rect(x-5,181,30,3,"#0c1920");rect(x,151+bob,18,4,dimAccent);rect(x-4,155+bob,26,17,accent);rect(x-1,172+bob,20,6,accent);rect(x+1,178,5,5,dimAccent);rect(x+12,178,5,5,dimAccent);rect(x-8,162+bob,4,7,dimAccent);rect(x+22,162+bob,4,7,dimAccent);rect(x+1,159+bob,5,5,"#17232b");rect(x+13,159+bob,5,5,"#17232b");rect(x+6,169+bob,7,2,"#4b704c");rect(x+7,146+bob,3,5,dimAccent);rect(x+6,144+bob,5,3,"#ef9b78");
      const pulse = time-signalTime.current;
      if(pulse>=0&&pulse<4){for(let i=0;i<7;i++){const px=95+((pulse*44+i*20)%190);const py=112+Math.sin(px*.06+time)*4;rect(px,py,3,3,i%2?accent:"#8fc8c4");}}
      // In-scene labels are decorative; full descriptions are outside the canvas.
      print("SIGNAL GARDEN",12,18,"#a9b9ad",7);print("ILLUSTRATION / NOT GAME OUTPUT",12,214,"#78918d",7);
      if(!paused) frame=requestAnimationFrame(draw);
    };
    frame=requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [paused, palette, reset, signal]);

  const sendSignal = () => {
    destination.current = (destination.current+1)%3;
    signalTime.current=elapsed.current;
    setSignal(value=>value+1);
  };
  const resetScene = () => { elapsed.current=0;destination.current=0;signalTime.current=-100;setSignal(0);setReset(value=>value+1); };

  return (
    <figure className="pixel-sandbox retro-window">
      <div className="window-bar"><span><span className="window-icon" aria-hidden="true"/> signal-garden.exe</span><span className="window-controls" aria-hidden="true"><i/><i/><i/></span></div>
      <div className="sandbox-screen"><canvas ref={canvas} width={384} height={224} role="img" aria-label="Original pixel-art illustration: a small yellow courier creature between a CPU terminal and an unfilled frame display, with a distant city and palm trees. This is not GTA VI gameplay."/></div>
      <div className="sandbox-toolbar"><span className="sandbox-state">{paused?"PAUSED":"RUNNING"} <span aria-hidden="true">·</span> illustration only</span><div><button type="button" onClick={()=>setPaused(value=>!value)} aria-pressed={paused}>{paused?"Resume":"Pause"}</button><button type="button" onClick={resetScene}>Reset</button><button type="button" onClick={sendSignal}>Send signal</button></div></div>
      <figcaption>Small original pixel world. Big runtime questions. <span>Not game output.</span></figcaption>
    </figure>
  );
}
