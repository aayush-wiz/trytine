import type { CSSProperties, ReactNode } from "react";
import { C, mono, sans } from "../lib/theme";

/** The small pill "eyebrow" badge used above section titles. */
export function Eyebrow({ children, style }: { children: ReactNode; style?: CSSProperties }) {
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        border: `1px solid ${C.brandBorder}`,
        color: C.brandSoft,
        fontFamily: mono,
        fontSize: 10,
        letterSpacing: "0.16em",
        textTransform: "uppercase",
        whiteSpace: "nowrap",
        padding: "7px 12px",
        borderRadius: 6,
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** Centered section header: eyebrow + big title, with the standard divider padding. */
export function SectionHead({ eyebrow, title }: { eyebrow: ReactNode; title: ReactNode }) {
  return (
    <div
      style={{
        padding: "56px 32px 44px",
        borderBottom: `1px solid ${C.faint}`,
        textAlign: "center",
      }}
    >
      <Eyebrow style={{ marginBottom: 20 }}>{eyebrow}</Eyebrow>
      <h2
        style={{
          fontWeight: 400,
          fontSize: "clamp(24px,3.2vw,42px)",
          lineHeight: 1.0,
          letterSpacing: "-0.02em",
          maxWidth: "20ch",
          margin: "0 auto",
        }}
      >
        {title}
      </h2>
    </div>
  );
}

/** Browser/window chrome with three dots and a title — wraps the product mockups. */
export function MockWindow({
  title,
  dark = false,
  children,
}: {
  title: string;
  dark?: boolean;
  children: ReactNode;
}) {
  const dot = dark ? "#3a3b44" : "#e0ddd4";
  return (
    <div
      style={{
        width: "100%",
        border: dark ? "none" : `1px solid ${C.faintBorder}`,
        borderRadius: 12,
        overflow: "hidden",
        background: dark ? "#15161b" : "#ffffff",
        boxShadow: dark
          ? "0 18px 44px -26px rgba(26,23,20,0.55)"
          : "0 18px 44px -28px rgba(26,23,20,0.4)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 7,
          padding: "11px 14px",
          borderBottom: dark ? "1px solid rgba(255,255,255,0.08)" : `1px solid ${C.faint}`,
          background: dark ? "#1c1d23" : "#f3f1ec",
        }}
      >
        <Dot color={dot} />
        <Dot color={dot} />
        <Dot color={dot} />
        <span style={{ marginLeft: 8, fontFamily: mono, fontSize: 11, color: dark ? "#8f8d86" : C.sub }}>
          {title}
        </span>
      </div>
      {children}
    </div>
  );
}

export function Dot({ color = "#d8d4cb", size = 9 }: { color?: string; size?: number }) {
  return <span style={{ width: size, height: size, borderRadius: "50%", background: color }} />;
}

/** A pulsing status dot (the "live"/working indicator). */
export function PulseDot({ speed = 1.6, size = 7 }: { speed?: number; size?: number }) {
  return (
    <span
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        background: C.brand,
        animation: `dotpulse ${speed}s ease-in-out infinite`,
      }}
    />
  );
}

/** A key/value row used inside the live mockups. */
export function KV({ k, v, vColor }: { k: string; v: ReactNode; vColor?: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", color: C.text2 }}>
      <span style={{ color: C.sub }}>{k}</span>
      <span style={{ color: vColor }}>{v}</span>
    </div>
  );
}

/** A checked progress line ("opened Gmail ✓"). */
export function Step({ label, done = true }: { label: string; done?: boolean }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", color: done ? C.text2 : C.sub }}>
      <span>{label}</span>
      <span style={{ color: done ? C.brandSoft : undefined }}>{done ? "✓" : "…"}</span>
    </div>
  );
}

/** Thin progress bar. */
export function ProgressBar({ pct }: { pct: number }) {
  return (
    <div
      style={{
        height: 4,
        borderRadius: 3,
        background: "rgba(26,23,20,0.1)",
        marginTop: 16,
        overflow: "hidden",
      }}
    >
      <div style={{ width: `${pct}%`, height: "100%", background: C.brand }} />
    </div>
  );
}

/** Primary / secondary buttons (anchors). */
export function Button({
  href,
  variant = "primary",
  disabled = false,
  children,
}: {
  href?: string;
  variant?: "primary" | "ghost";
  disabled?: boolean;
  children: ReactNode;
}) {
  const base: CSSProperties = {
    fontFamily: mono,
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: "0.05em",
    textTransform: "uppercase",
    padding: "10px 17px",
    borderRadius: 6,
    textDecoration: "none",
    display: "inline-block",
  };
  if (disabled) {
    return (
      <span
        aria-disabled="true"
        style={{ ...base, background: C.softBlue, color: C.ink, opacity: 0.6, cursor: "not-allowed", pointerEvents: "none" }}
      >
        {children}
      </span>
    );
  }
  if (variant === "primary") {
    return (
      <a href={href} className="hv-brand" style={{ ...base, background: C.softBlue, color: C.ink }}>
        {children}
      </a>
    );
  }
  return (
    <a
      href={href}
      className="hv-ink"
      style={{ ...base, background: "transparent", color: C.ink, border: "1px solid rgba(26,23,20,0.22)" }}
    >
      {children}
    </a>
  );
}

export const monoText: CSSProperties = { fontFamily: mono };
export const sansText: CSSProperties = { fontFamily: sans };
