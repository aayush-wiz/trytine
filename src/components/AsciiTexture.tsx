import { mono } from "../lib/theme";
import { ASCII_TEXTURE } from "../content";

/** Faint repeating ASCII art used as a background texture in the brand-colored sections. */
export function AsciiTexture({ color = "rgba(255,255,255,0.13)" }: { color?: string }) {
  return (
    <pre
      aria-hidden
      style={{
        position: "absolute",
        inset: 0,
        margin: 0,
        fontFamily: mono,
        fontSize: 13,
        lineHeight: "16px",
        letterSpacing: 1,
        color,
        whiteSpace: "pre",
        overflow: "hidden",
        pointerEvents: "none",
        userSelect: "none",
      }}
    >
      {ASCII_TEXTURE}
    </pre>
  );
}
