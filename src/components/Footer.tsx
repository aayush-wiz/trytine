import { C, mono } from "../lib/theme";

const SOCIALS = [
  {
    label: "X",
    path: "M18.24 2H21.5l-7.5 8.57L23 22h-6.84l-5.36-7-6.13 7H1.4l8.02-9.17L1 2h7l4.84 6.4L18.24 2zm-1.2 18h1.9L7.04 4H5l12.04 16z",
    size: 14,
  },
  {
    label: "GitHub",
    path: "M12 .5C5.37.5 0 5.87 0 12.5c0 5.3 3.44 9.8 8.21 11.39.6.11.82-.26.82-.58v-2.03c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.34-1.76-1.34-1.76-1.09-.75.08-.73.08-.73 1.2.08 1.84 1.24 1.84 1.24 1.07 1.83 2.81 1.3 3.5.99.11-.78.42-1.3.76-1.6-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.13-.3-.54-1.52.12-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.29-1.55 3.3-1.23 3.3-1.23.66 1.66.25 2.88.12 3.18.77.84 1.23 1.91 1.23 3.22 0 4.61-2.8 5.62-5.48 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58A12.01 12.01 0 0 0 24 12.5C24 5.87 18.63.5 12 .5z",
    size: 15,
  },
  {
    label: "LinkedIn",
    path: "M4.98 3.5C4.98 4.88 3.87 6 2.5 6S0 4.88 0 3.5 1.12 1 2.5 1 4.98 2.12 4.98 3.5zM0 8h5v16H0V8zm7.5 0h4.8v2.2h.07c.67-1.2 2.3-2.46 4.73-2.46C22 7.74 24 10 24 14.2V24h-5v-8.7c0-2.07-.04-4.74-2.9-4.74-2.9 0-3.35 2.26-3.35 4.6V24h-5V8z",
    size: 15,
  },
];

export function Footer() {
  return (
    <footer
      style={{
        position: "relative",
        background: C.bg,
        backgroundImage: "radial-gradient(rgba(26,23,20,0.1) 1px,transparent 1px)",
        backgroundSize: "22px 22px",
        borderTop: `1px solid ${C.faint}`,
        padding: "38px 32px 24px",
        overflow: "hidden",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 18, fontFamily: mono, fontSize: 12, color: C.sub, flexWrap: "wrap" }}>
        <span style={{ whiteSpace: "nowrap" }}>San Francisco · Remote-first</span>
        <span style={{ color: "rgba(26,23,20,0.22)" }}>|</span>
        <span>hello@trytine.com</span>
      </div>

      <div style={{ textAlign: "center", padding: "10px 0 4px" }}>
        <span style={{ fontWeight: 800, fontSize: "clamp(72px,18vw,220px)", letterSpacing: "-0.05em", lineHeight: 0.82, color: C.ink }}>
          tine
        </span>
      </div>

      <div style={{ height: 1, background: "rgba(26,23,20,0.13)", margin: "6px 0 16px" }} />

      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 14, flexWrap: "wrap" }}>
        <span style={{ fontFamily: mono, fontSize: 11, color: C.sub, whiteSpace: "nowrap" }}>© 2026 Tine Computer, Inc.</span>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          {SOCIALS.map((s) => (
            <a key={s.label} href="#" aria-label={s.label} style={{ display: "flex" }}>
              <svg width={s.size} height={s.size} viewBox="0 0 24 24" fill="#3a352e">
                <path d={s.path} />
              </svg>
            </a>
          ))}
        </div>
        <a href="#" className="hv-link" style={{ fontFamily: mono, fontSize: 11, color: C.sub, textDecoration: "none" }}>
          Privacy &amp; Terms
        </a>
      </div>
    </footer>
  );
}
