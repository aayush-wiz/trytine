import { useRef, useState } from "react";
import { C, mono } from "../lib/theme";
import { Eyebrow } from "./ui";
import { AsciiTexture } from "./AsciiTexture";

export function Demo() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);

  const onPlay = () => {
    setPlaying(true);
    const v = videoRef.current;
    if (v) {
      if (!v.src) v.src = "/perch-demo.mp4";
      v.play().catch(() => {});
    }
  };

  return (
    <section id="demo" style={{ background: C.bg, borderTop: `1px solid ${C.faint}` }}>
      <div style={{ padding: "56px 32px 44px", borderBottom: `1px solid ${C.faint}`, textAlign: "center" }}>
        <Eyebrow style={{ marginBottom: 20 }}>▶ See it live</Eyebrow>
        <h2
          style={{
            fontWeight: 400,
            fontSize: "clamp(24px,3.2vw,42px)",
            lineHeight: 1.0,
            letterSpacing: "-0.02em",
            margin: "0 auto",
          }}
        >
          Watch Tine work.
        </h2>
      </div>

      <div
        style={{
          position: "relative",
          overflow: "hidden",
          background: C.softBlue,
          padding: "clamp(20px,2.4vw,32px) clamp(16px,2vw,28px)",
          boxShadow: "inset 0 0 0 1px rgba(58,108,176,0.28)",
        }}
      >
        <AsciiTexture color={C.softBlueTexture} />
        <div
          style={{
            position: "relative",
            zIndex: 1,
            maxWidth: 1180,
            margin: "0 auto",
            width: "100%",
            aspectRatio: "16 / 9",
            background: "#1a1714",
            borderRadius: 11,
            overflow: "hidden",
            boxShadow: "0 22px 48px -22px rgba(0,0,0,0.65)",
          }}
        >
          <video
            ref={videoRef}
            controls
            playsInline
            preload="metadata"
            poster="/perch-poster.jpg"
            style={{ width: "100%", height: "100%", objectFit: "cover", display: "block", background: "#1a1714" }}
          />

          {!playing && (
            <button
              onClick={onPlay}
              aria-label="Play demo"
              style={{
                position: "absolute",
                inset: 0,
                width: "100%",
                height: "100%",
                border: "none",
                cursor: "pointer",
                padding: 0,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: "linear-gradient(180deg, rgba(20,18,16,0.15), rgba(20,18,16,0.45))",
              }}
            >
              <div
                style={{
                  position: "absolute",
                  left: "60%",
                  top: "38%",
                  display: "flex",
                  alignItems: "flex-start",
                  gap: 8,
                  pointerEvents: "none",
                }}
              >
                <svg width="22" height="32" viewBox="0 0 14 20" style={{ filter: "drop-shadow(0 4px 10px rgba(26,23,20,0.25))" }}>
                  <path
                    d="M1 1 L1 17.6 L5.2 13.7 L7.7 19.9 L9.9 18.9 L7.4 12.8 L13 12.8 Z"
                    fill={C.brand}
                    stroke="#1a1714"
                    strokeWidth={1.1}
                    strokeLinejoin="round"
                  />
                </svg>
                <span
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    background: "#fff",
                    border: `1px solid ${C.brandBorderStrong}`,
                    borderRadius: 9,
                    padding: "6px 9px",
                    boxShadow: "0 10px 24px -12px rgba(26,23,20,0.4)",
                  }}
                >
                  <span style={{ width: 5, height: 5, borderRadius: "50%", background: C.brandText }} />
                  <span style={{ width: 5, height: 5, borderRadius: "50%", background: C.brandText }} />
                  <span style={{ fontFamily: mono, fontSize: 10, color: C.ink, whiteSpace: "nowrap" }}>on it</span>
                </span>
              </div>

              <span
                style={{
                  position: "relative",
                  zIndex: 2,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  width: 72,
                  height: 72,
                  borderRadius: "50%",
                  background: C.brand,
                  boxShadow: "0 16px 40px -14px oklch(0.5 0.16 255)",
                }}
              >
                <span
                  style={{
                    width: 0,
                    height: 0,
                    borderTop: "13px solid transparent",
                    borderBottom: "13px solid transparent",
                    borderLeft: "20px solid #fff",
                    marginLeft: 5,
                  }}
                />
              </span>
              <span
                style={{
                  position: "absolute",
                  bottom: 18,
                  left: "50%",
                  transform: "translateX(-50%)",
                  fontFamily: mono,
                  fontSize: 11,
                  letterSpacing: "0.06em",
                  color: C.sub,
                }}
              >
                2 min · Tine in action
              </span>
            </button>
          )}
        </div>
      </div>
    </section>
  );
}
