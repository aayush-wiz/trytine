import { C, mono } from "../lib/theme";
import { MODES } from "../content";
import { SectionHead } from "./ui";

export function Modes() {
  return (
    <section id="modes" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <SectionHead eyebrow="◇ How it works" title="Three ways it shows up." />

      {/* the three modes — a horizontal row across the top */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", borderBottom: `1px solid ${C.faint}` }}>
        {MODES.map((m, i) => (
          <div
            key={m.id}
            style={{
              padding: "28px 30px 32px",
              borderRight: i < MODES.length - 1 ? `1px solid ${C.faint}` : undefined,
              borderTop: `3px solid ${C.brand}`,
            }}
          >
            <div
              style={{
                fontFamily: mono,
                fontSize: 10,
                letterSpacing: "0.18em",
                textTransform: "uppercase",
                whiteSpace: "nowrap",
                color: C.brandSoft,
              }}
            >
              {m.kicker}
            </div>
            <h3
              style={{
                fontWeight: 500,
                fontSize: "clamp(19px,2.2vw,26px)",
                lineHeight: 1.08,
                letterSpacing: "-0.015em",
                margin: "12px 0 0",
              }}
            >
              {m.title}
            </h3>
            <p style={{ fontSize: 13, lineHeight: 1.6, color: C.muted2, margin: "12px 0 0", maxWidth: "34ch" }}>
              {m.body}
            </p>
          </div>
        ))}
      </div>

      {/* the live notch animation — full width below the tabs, over the cloud background */}
      <div style={{ padding: 26 }}>
        <div
          style={{
            position: "relative",
            width: "100%",
            aspectRatio: "1200 / 800",
            borderRadius: 16,
            overflow: "hidden",
            background: "#a9cfee url(/clouds.jpg) center / cover no-repeat",
          }}
        >
          <iframe
            src="/notch-demo.html"
            title="Tine in action"
            style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: "none", display: "block", background: "transparent" }}
            allow="transparency"
          />
        </div>
      </div>
    </section>
  );
}
