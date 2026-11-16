import { useMemo } from "react";
import { C, mono } from "../lib/theme";
import { asciiCursor } from "../lib/asciiCursor";
import { useTypewriter } from "../hooks/useTypewriter";
import { HERO_PHRASES, TICKER } from "../content";
import { Button } from "./ui";
import { Logo } from "./Logo";
import { useEarlyAccess } from "./EarlyAccess";

export function Hero() {
  const cursor = useMemo(() => asciiCursor(22), []);
  const typed = useTypewriter(HERO_PHRASES);
  const { open } = useEarlyAccess();

  return (
    <section style={{ position: "relative", background: C.bg, overflow: "hidden" }}>
      {/* nav */}
      <nav
        style={{
          position: "relative",
          zIndex: 2,
          padding: "18px 28px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          borderBottom: `1px solid ${C.faint}`,
        }}
      >
        <Logo />
        <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
          <button
            type="button"
            onClick={open}
            className="hv-brand"
            style={{
              fontFamily: mono,
              fontSize: 11,
              fontWeight: 600,
              letterSpacing: "0.06em",
              textTransform: "uppercase",
              background: C.softBlue,
              color: C.ink,
              padding: "9px 15px",
              borderRadius: 6,
              border: "none",
              cursor: "pointer",
              whiteSpace: "nowrap",
            }}
          >
            Get early access
          </button>
        </div>
      </nav>

      {/* top hero: copy on the left, floating ASCII cursor on the right */}
      <div style={{ position: "relative", overflow: "hidden" }}>
        {/* ASCII cursor + floating command bar */}
        <div
          aria-hidden
          style={{
            position: "absolute",
            top: 0,
            right: "4%",
            width: "46%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1,
            pointerEvents: "none",
          }}
        >
          <div style={{ position: "relative", animation: "floaty 6s ease-in-out infinite" }}>
            <pre
              style={{
                margin: 0,
                fontFamily: mono,
                fontSize: 9,
                lineHeight: "8px",
                color: C.softBlue,
                whiteSpace: "pre",
                textShadow: "0 0 16px rgba(120,170,225,0.5)",
              }}
            >
              {cursor}
            </pre>
          </div>
          <div
            style={{
              position: "absolute",
              top: "32%",
              left: "40%",
              width: 250,
              display: "flex",
              alignItems: "center",
              gap: 8,
              background: "#fff",
              border: `1px solid ${C.softBlue}`,
              borderRadius: 8,
              padding: "5px 10px",
              boxShadow: "0 12px 30px -16px rgba(26,23,20,0.5)",
            }}
          >
            <span
              style={{
                flex: 1,
                display: "flex",
                alignItems: "center",
                minWidth: 0,
                fontFamily: mono,
                fontSize: 11,
                color: C.ink,
              }}
            >
              <span style={{ whiteSpace: "nowrap", overflow: "hidden" }}>{typed}</span>
              <span
                style={{
                  display: "inline-block",
                  width: 2,
                  height: 13,
                  background: C.brandSoft,
                  marginLeft: 2,
                  flex: "none",
                  animation: "caretblink 1s steps(1) infinite",
                }}
              />
            </span>
            <span style={{ flex: "none", color: C.sub, fontSize: 12 }}>⏎</span>
          </div>
        </div>

        {/* hero copy */}
        <div style={{ position: "relative", zIndex: 2, padding: "48px 28px 40px", textAlign: "left", maxWidth: 500 }}>
          <h1
            style={{
              fontWeight: 400,
              fontSize: "clamp(24px,3.4vw,40px)",
              lineHeight: 1.02,
              letterSpacing: "-0.02em",
              maxWidth: "20ch",
              margin: 0,
            }}
          >
            A second cursor that watches, helps, and does the work.
          </h1>
          <div style={{ display: "flex", gap: 10, marginTop: 26, flexWrap: "wrap" }}>
            <Button disabled>Download for Mac (coming soon)</Button>
            <Button href="#demo" variant="ghost">
              Watch it work
            </Button>
          </div>
        </div>
      </div>

      {/* pixel-assemble animation — a living tile field, right below the heading */}
      <div style={{ position: "relative", zIndex: 2, borderTop: `1px solid ${C.faint}`, background: C.bg }}>
        <iframe
          src="/pixel-assemble.html"
          title="Tine — a living tile field (hover to reveal the scene)"
          scrolling="no"
          loading="eager"
          style={{ display: "block", width: "100%", aspectRatio: "2660 / 1502", border: 0, background: C.bg }}
        />
      </div>

      {/* ticker bar */}
      <div style={{ position: "relative", overflow: "hidden", background: C.softBlue }}>
        <div
          style={{
            position: "relative",
            zIndex: 2,
            padding: "16px 28px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: "14px 28px",
            flexWrap: "wrap",
            fontSize: 15,
            fontWeight: 500,
            letterSpacing: "-0.005em",
            color: C.ink,
          }}
        >
          {TICKER.map((t) => (
            <span key={t} style={{ display: "inline-flex", alignItems: "center", gap: 14 }}>
              <span style={{ color: C.brandSoft }}>▸</span>
              {t}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
