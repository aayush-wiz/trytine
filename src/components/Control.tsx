import { C, mono } from "../lib/theme";
import { CONTROL_POINTS, CONTROL_STATS } from "../content";

export function Control() {
  return (
    <section id="control" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <div style={{ padding: "54px 32px 48px", borderBottom: `1px solid ${C.faint}`, textAlign: "center" }}>
        <div
          style={{
            fontFamily: mono,
            fontSize: 10,
            letterSpacing: "0.16em",
            textTransform: "uppercase",
            color: C.brandSoft,
            marginBottom: 18,
          }}
        >
          You're always in charge
        </div>
        <h2
          style={{
            fontWeight: 400,
            fontSize: "clamp(22px,2.8vw,36px)",
            lineHeight: 1.05,
            letterSpacing: "-0.02em",
            maxWidth: "24ch",
            margin: "0 auto 32px",
          }}
        >
          It only ever does what you let it.
        </h2>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: "11px 48px",
            maxWidth: 680,
            margin: "0 auto",
            textAlign: "left",
            fontFamily: mono,
            fontSize: 12.5,
            lineHeight: 1.5,
            color: "rgba(26,23,20,0.72)",
          }}
        >
          {CONTROL_POINTS.map((p) => (
            <div key={p} style={{ display: "flex", gap: 10 }}>
              <span style={{ color: C.brandText }}>→</span>
              {p}
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)" }}>
        {CONTROL_STATS.map((s, i) => (
          <div
            key={s.label}
            style={{
              padding: "34px 16px",
              borderRight: i < 3 ? `1px solid ${C.faint}` : undefined,
              textAlign: "center",
            }}
          >
            <div
              style={{
                fontWeight: 400,
                fontSize: "clamp(20px,2.4vw,30px)",
                letterSpacing: "-0.02em",
                color: s.brand ? C.brandSoft : undefined,
              }}
            >
              {s.big}
            </div>
            <div style={{ fontFamily: mono, fontSize: 10, letterSpacing: "0.12em", textTransform: "uppercase", color: C.sub, marginTop: 8 }}>
              {s.label}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
