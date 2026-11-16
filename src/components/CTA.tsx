import { C, mono } from "../lib/theme";
import { useEarlyAccess } from "./EarlyAccess";

export function CTA() {
  const { open } = useEarlyAccess();

  return (
    <section
      id="cta"
      style={{ position: "relative", background: C.softBlue, color: C.ink, overflow: "hidden", borderTop: `1px solid ${C.faint}` }}
    >
      {/* cloud image as the section background */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage: "url(/clouds.jpg)",
          backgroundSize: "cover",
          backgroundPosition: "center",
          backgroundRepeat: "no-repeat",
        }}
      />
      <div style={{ position: "relative", zIndex: 2, padding: "62px 32px 104px", textAlign: "center" }}>
        <h2 style={{ fontWeight: 400, fontSize: "clamp(26px,3.6vw,48px)", lineHeight: 1.0, letterSpacing: "-0.02em" }}>
          Give your cursor a sidekick.
        </h2>
        <button
          type="button"
          onClick={open}
          className="hv-dark"
          style={{
            fontFamily: mono,
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: "0.06em",
            textTransform: "uppercase",
            background: "#1a1714",
            color: "#faf8f3",
            padding: "14px 28px",
            borderRadius: 7,
            border: "none",
            cursor: "pointer",
            marginTop: 26,
          }}
        >
          Get early access
        </button>
      </div>
    </section>
  );
}
