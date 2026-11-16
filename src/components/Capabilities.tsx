import { C, mono } from "../lib/theme";
import { FEATURES } from "../content";
import { SectionHead } from "./ui";

export function Capabilities() {
  return (
    <section id="features" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <SectionHead eyebrow="⊞ What it can do" title="Less busywork, more you." />

      <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)" }}>
        {FEATURES.map((f, i) => {
          const col = i % 3;
          const row = Math.floor(i / 3);
          return (
            <div
              key={f.n}
              className="hv-row"
              style={{
                padding: "30px 26px",
                borderRight: col < 2 ? `1px solid ${C.faint}` : undefined,
                borderBottom: row < 1 ? `1px solid ${C.faint}` : undefined,
              }}
            >
              <div style={{ fontFamily: mono, fontSize: 12, letterSpacing: "0.22em", color: C.brandSoft, marginBottom: 22 }}>
                [ {f.n} ]
              </div>
              <h3 style={{ fontWeight: 500, fontSize: 20, lineHeight: 1.12, letterSpacing: "-0.012em", marginBottom: 14 }}>
                {f.title}
              </h3>
              <p style={{ fontSize: 13, lineHeight: 1.6, color: C.muted2 }}>{f.body}</p>
            </div>
          );
        })}
      </div>
    </section>
  );
}
