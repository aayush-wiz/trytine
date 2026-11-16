import { C, mono } from "../lib/theme";
import { SectionHead } from "./ui";

/** Hands-free voice section — a looping demo of the notch listening and running a spoken command. */
export function Voice() {
  const points = [
    "Press a hotkey, say what you want",
    "Live transcript as you speak",
    "It hears you, not the room",
    "Runs while you keep working",
  ];
  return (
    <section id="voice" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <SectionHead eyebrow="✦ Hands-free" title="Just say it." />

      {/* the looping notch animation — full width, fixed short height */}
      <div style={{ padding: "28px 32px 8px" }}>
        <div
          style={{
            position: "relative",
            width: "100%",
            height: 300,
            borderRadius: 16,
            overflow: "hidden",
            border: `1px solid ${C.faint}`,
            background: "#a9cfee url(/clouds.jpg) center / cover no-repeat",
          }}
        >
          <iframe
            src="/voice-demo.html"
            title="Talk to Tine"
            style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: "none", display: "block", background: "transparent" }}
          />
        </div>
      </div>

      {/* copy + points below */}
      <div style={{ padding: "20px 32px 52px", maxWidth: 880, margin: "0 auto", textAlign: "center" }}>
        <p style={{ fontSize: 15, lineHeight: 1.65, color: C.muted2, margin: "0 auto 26px", maxWidth: "56ch" }}>
          Talk to Tine like a teammate. It listens through the notch, locks onto your voice — not the TV
          or the room — and runs the task across your apps while you keep working.
        </p>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(2, minmax(0,1fr))",
            gap: "11px 48px",
            maxWidth: 620,
            margin: "0 auto",
            textAlign: "left",
            fontFamily: mono,
            fontSize: 12.5,
            lineHeight: 1.5,
            color: "rgba(26,23,20,0.72)",
          }}
        >
          {points.map((p) => (
            <div key={p} style={{ display: "flex", gap: 10 }}>
              <span style={{ color: C.brandText }}>→</span>
              {p}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
