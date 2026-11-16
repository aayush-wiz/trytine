// Central design tokens — colors + fonts used across the landing page.
export const C = {
  bg: "#faf8f3",
  ink: "#1a1714",
  brand: "oklch(0.55 0.16 255)",
  brandHi: "oklch(0.62 0.16 255)",
  brandSoft: "oklch(0.5 0.15 255)",
  brandText: "oklch(0.52 0.15 255)",
  brandBorder: "oklch(0.6 0.13 255 / 0.5)",
  brandBorderStrong: "oklch(0.6 0.13 255 / 0.55)",
  softBlue: "#a9cfee", // pale sky-blue for the big "blue background" sections (CTA, How-it-works panel)
  softBlueTexture: "rgba(58,108,176,0.16)", // darker tint so the ASCII texture reads on the pale-blue bg
  muted: "rgba(26,23,20,0.66)",
  muted2: "rgba(26,23,20,0.6)",
  faint: "rgba(26,23,20,0.12)",
  faintBorder: "rgba(26,23,20,0.14)",
  sub: "#6f6a62",
  text2: "#3a352e",
} as const;

export const mono = "'IBM Plex Mono', monospace";
export const sans = "'Archivo', sans-serif";
