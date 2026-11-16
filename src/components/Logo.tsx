/** The tine wordmark + blue triangle-pointer glyph (same icon as the favicon / Swift app). */
export function Logo() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
      <svg width="21" height="21" viewBox="0 0 22 22" aria-hidden style={{ display: "block" }}>
        <polygon points="11,2 4,20 11,16 18,20" fill="#007AFF" />
      </svg>
      <span style={{ fontWeight: 700, fontSize: 17, letterSpacing: "-0.02em" }}>Tine</span>
    </div>
  );
}
