import { createContext, useContext, useState, type FormEvent, type ReactNode } from "react";
import { C, mono } from "../lib/theme";

// Google Apps Script Web App URL (ends with /exec) that appends each signup to the Sheet.
const SIGNUP_ENDPOINT =
  "https://script.google.com/macros/s/AKfycbyhyBPkEabnFYRY8k7Ci7mG9-BEFmSMykMXZdusMmUNywdIazDndqO_ulne7Oy-gCwRaQ/exec";

const Ctx = createContext<{ open: () => void }>({ open: () => {} });
export const useEarlyAccess = () => useContext(Ctx);

/** Wrap the app so any button can call useEarlyAccess().open() to show the signup modal. */
export function EarlyAccessProvider({ children }: { children: ReactNode }) {
  const [isOpen, setOpen] = useState(false);
  return (
    <Ctx.Provider value={{ open: () => setOpen(true) }}>
      {children}
      {isOpen && <EarlyAccessModal onClose={() => setOpen(false)} />}
    </Ctx.Provider>
  );
}

function EarlyAccessModal({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [joined, setJoined] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setJoined(true);
    try {
      await fetch(SIGNUP_ENDPOINT, {
        method: "POST",
        mode: "no-cors", // Apps Script web apps don't return CORS headers — fire-and-forget
        headers: { "Content-Type": "text/plain;charset=utf-8" }, // avoids a CORS preflight
        body: JSON.stringify({ name, email }),
      });
    } catch {
      /* swallow network errors — the visitor still sees a confirmation */
    }
  };

  const inputStyle = {
    fontFamily: mono,
    fontSize: 13,
    padding: "13px 16px",
    borderRadius: 7,
    border: `1px solid ${C.faintBorder}`,
    background: "#fff",
    color: C.ink,
    outline: "none",
    width: "100%",
  } as const;

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 1000,
        background: "rgba(20,18,15,0.55)",
        backdropFilter: "blur(4px)",
        WebkitBackdropFilter: "blur(4px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 24,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          position: "relative",
          width: "100%",
          maxWidth: 400,
          background: C.bg,
          border: `1px solid ${C.faintBorder}`,
          borderRadius: 16,
          padding: "32px 28px",
          boxShadow: "0 40px 90px -30px rgba(26,23,20,0.6)",
          textAlign: "center",
        }}
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          style={{
            position: "absolute",
            top: 14,
            right: 14,
            width: 30,
            height: 30,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 8,
            border: "none",
            background: "transparent",
            color: C.sub,
            cursor: "pointer",
            padding: 0,
          }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>

        <div style={{ display: "flex", justifyContent: "center", marginBottom: 12 }}>
          <svg width="26" height="26" viewBox="0 0 22 22" aria-hidden>
            <polygon points="11,2 4,20 11,16 18,20" fill="#007AFF" />
          </svg>
        </div>

        <h3 style={{ fontWeight: 500, fontSize: 24, letterSpacing: "-0.02em", margin: 0 }}>Get early access</h3>

        {joined ? (
          <div style={{ fontFamily: mono, fontSize: 13, lineHeight: 1.6, color: C.ink, margin: "20px 0 4px" }}>
            ✦ You're on the list — we'll email you when early access opens.
          </div>
        ) : (
          <>
            <p style={{ fontFamily: mono, fontSize: 12.5, lineHeight: 1.6, color: C.muted2, margin: "10px auto 0", maxWidth: "34ch" }}>
              Be first in line — drop your name and email and we'll reach out when Tine opens.
            </p>
            <form onSubmit={submit} style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: 22 }}>
              <input type="text" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Your name" autoComplete="name" style={inputStyle} />
              <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@email.com" autoComplete="email" style={inputStyle} />
              <button
                type="submit"
                className="hv-dark"
                style={{
                  fontFamily: mono,
                  fontSize: 12,
                  fontWeight: 600,
                  letterSpacing: "0.06em",
                  textTransform: "uppercase",
                  background: "#1a1714",
                  color: "#faf8f3",
                  padding: "13px 24px",
                  borderRadius: 7,
                  border: "none",
                  cursor: "pointer",
                  marginTop: 2,
                }}
              >
                Get early access
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
