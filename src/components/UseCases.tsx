import { useEffect, useRef, useState, type ReactNode } from "react";
import { C, mono, sans } from "../lib/theme";
import { SectionHead } from "./ui";

const TASK_VIDEOS = [
  { src: "/perch-task-1.mp4", label: "Calendar" },
  { src: "/perch-task-2.mp4", label: "Slack" },
  { src: "/perch-task-3.mp4", label: "Stock" },
];

function Copy({ kicker, title, body, bullets }: { kicker: string; title: string; body: string; bullets: string[] }) {
  return (
    <div style={{ padding: "48px 40px", display: "flex", flexDirection: "column", justifyContent: "center" }}>
      <div
        style={{
          fontFamily: sans,
          fontWeight: 600,
          fontSize: 12,
          letterSpacing: "0.01em",
          color: C.brandSoft,
        }}
      >
        {kicker}
      </div>
      <h3
        style={{
          fontWeight: 500,
          fontSize: "clamp(22px,2.6vw,32px)",
          lineHeight: 1.08,
          letterSpacing: "-0.018em",
          margin: "14px 0 14px",
          maxWidth: "18ch",
        }}
      >
        {title}
      </h3>
      <p style={{ fontSize: 14, lineHeight: 1.62, color: C.muted, maxWidth: "42ch" }}>{body}</p>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 20, fontFamily: mono, fontSize: 12, color: "rgba(26,23,20,0.7)" }}>
        {bullets.map((b) => (
          <div key={b} style={{ display: "flex", gap: 8 }}>
            <span style={{ color: C.brandText }}>→</span>
            {b}
          </div>
        ))}
      </div>
    </div>
  );
}

function MockCell({ children }: { children: ReactNode }) {
  return <div style={{ padding: "40px 36px", display: "flex", alignItems: "center" }}>{children}</div>;
}

function VideoFrame({ src, aspect, onExpand }: { src: string; aspect: string; onExpand: () => void }) {
  const ref = useRef<HTMLVideoElement>(null);
  // Don't download the clip until it scrolls into view; play while visible, pause when not.
  useEffect(() => {
    const v = ref.current;
    if (!v) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) v.play().catch(() => {});
        else v.pause();
      },
      { threshold: 0.2 },
    );
    io.observe(v);
    return () => io.disconnect();
  }, []);
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        aspectRatio: aspect,
        background: "#1a1714",
        borderRadius: 11,
        overflow: "hidden",
        boxShadow: "0 22px 48px -22px rgba(0,0,0,0.55)",
      }}
    >
      <video ref={ref} src={src} loop muted playsInline preload="none" style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      <button
        type="button"
        onClick={onExpand}
        aria-label="Expand video"
        title="Expand"
        style={{
          position: "absolute",
          top: 10,
          right: 10,
          width: 30,
          height: 30,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          border: "1px solid rgba(255,255,255,0.28)",
          borderRadius: 8,
          background: "rgba(20,18,15,0.55)",
          backdropFilter: "blur(6px)",
          WebkitBackdropFilter: "blur(6px)",
          color: "#fff",
          cursor: "pointer",
          padding: 0,
        }}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="15 3 21 3 21 9" />
          <polyline points="9 21 3 21 3 15" />
          <line x1="21" y1="3" x2="14" y2="10" />
          <line x1="3" y1="21" x2="10" y2="14" />
        </svg>
      </button>
    </div>
  );
}

export function UseCases() {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <section id="usecases" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <SectionHead eyebrow="◳ Use cases" title="See it in your day." />

      {/* 01 — everyday tasks (centered heading + 3 demo videos in a row) */}
      <div style={{ borderBottom: `1px solid ${C.faint}` }}>
        <div style={{ padding: "48px 40px 6px", display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center" }}>
          <div
            style={{
              fontFamily: sans,
              fontWeight: 600,
              fontSize: 12,
              letterSpacing: "0.01em",
              color: C.brandSoft,
            }}
          >
            01 · Everyday tasks
          </div>
          <h3
            style={{
              fontWeight: 500,
              fontSize: "clamp(22px,2.6vw,32px)",
              lineHeight: 1.08,
              letterSpacing: "-0.018em",
              margin: "14px 0 14px",
              maxWidth: "22ch",
            }}
          >
            It runs the busywork end to end.
          </h3>
          <p style={{ fontSize: 14, lineHeight: 1.62, color: C.muted, maxWidth: "54ch", margin: "0 auto" }}>
            Tell Tine what you need and watch it go — it opens Gmail, drafts the reply in your voice, searches the web for
            what it needs, and stops just short of anything it shouldn't do without you.
          </p>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 20, padding: "30px 40px 48px" }}>
          {TASK_VIDEOS.map(({ src, label }) => (
            <div key={src}>
              <div
                style={{
                  fontFamily: sans,
                  fontWeight: 600,
                  fontSize: 14,
                  letterSpacing: "0.01em",
                  color: C.brandSoft,
                  textAlign: "center",
                  marginBottom: 12,
                }}
              >
                {label}
              </div>
              <VideoFrame src={src} aspect="3324 / 2160" onExpand={() => setExpanded(src)} />
            </div>
          ))}
        </div>
      </div>

      {/* 02 — inline writing (mock left / copy right) */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", borderBottom: `1px solid ${C.faint}` }}>
        <div style={{ borderRight: `1px solid ${C.faint}` }}>
          <MockCell>
            <div
              style={{
                position: "relative",
                width: "100%",
                aspectRatio: "16 / 10",
                borderRadius: 11,
                overflow: "hidden",
                background: "#a9cfee url(/clouds.jpg) center / cover no-repeat",
              }}
            >
              <iframe
                src="/inline-demo.html"
                title="Inline writing"
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: "none", display: "block", background: "transparent" }}
              />
            </div>
          </MockCell>
        </div>
        <Copy
          kicker="02 · Inline writing"
          title="It writes right where you type."
          body="As you write an email, a doc, or a message, Tine finishes the thought in your tone — appearing as ghost text inline. One tab to accept, keep typing to ignore. No window-hopping, no copy-paste."
          bullets={["matches your voice and context", "works in any text field"]}
        />
      </div>

      {/* 03 — dynamic island (copy left / video right) */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", borderBottom: `1px solid ${C.faint}` }}>
        <div style={{ borderRight: `1px solid ${C.faint}` }}>
          <Copy
            kicker="03 · Dynamic Island"
            title="Run your day from the island."
            body="Kick off everyday tasks from a Dynamic-Island-style pill in the notch. Tine shows each step as it works and keeps a live activity log you can glance at any time — no window to open, no app to manage."
            bullets={["one tap to start a task", "a running log of everything it does"]}
          />
        </div>
        <MockCell>
          <div
            style={{
              position: "relative",
              width: "100%",
              aspectRatio: "3324 / 2160",
              borderRadius: 11,
              overflow: "hidden",
              background: "#a9cfee url(/clouds.jpg) center / cover no-repeat",
            }}
          >
            <iframe
              src="/island-demo.html"
              title="Run a task from the island"
              style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: "none", display: "block", background: "transparent" }}
            />
          </div>
        </MockCell>
      </div>

      {/* 04 — teach by demonstration (video left / copy right) */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr" }}>
        <div style={{ borderRight: `1px solid ${C.faint}` }}>
          <MockCell>
            <div
              style={{
                position: "relative",
                width: "100%",
                aspectRatio: "3324 / 2160",
                borderRadius: 11,
                overflow: "hidden",
                background: "#a9cfee url(/clouds.jpg) center / cover no-repeat",
              }}
            >
              <iframe
                src="/teach-demo.html"
                title="Teach Tine a skill"
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: "none", display: "block", background: "transparent" }}
              />
            </div>
          </MockCell>
        </div>
        <Copy
          kicker="04 · Teach by demonstration"
          title="Show it once. It does it forever."
          body="Record yourself doing a task one time — Tine turns your clicks and keystrokes into a named skill. Next time, just ask, and the cursor replays it end to end, adapting to whatever's on screen."
          bullets={["records your real actions into a skill", "replays it on demand, hands-free"]}
        />
      </div>

      {expanded && (
        <div
          onClick={() => setExpanded(null)}
          role="dialog"
          aria-modal="true"
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 1000,
            background: "rgba(10,9,8,0.86)",
            backdropFilter: "blur(4px)",
            WebkitBackdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: 24,
          }}
        >
          <button
            type="button"
            onClick={() => setExpanded(null)}
            aria-label="Close"
            title="Close"
            style={{
              position: "absolute",
              top: 20,
              right: 24,
              width: 38,
              height: 38,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              borderRadius: 10,
              border: "1px solid rgba(255,255,255,0.25)",
              background: "rgba(20,18,15,0.6)",
              color: "#fff",
              cursor: "pointer",
              padding: 0,
            }}
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
          <video
            src={expanded}
            controls
            autoPlay
            loop
            playsInline
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: "92vw", maxHeight: "88vh", borderRadius: 12, boxShadow: "0 30px 80px -20px rgba(0,0,0,0.8)", background: "#000" }}
          />
        </div>
      )}
    </section>
  );
}
