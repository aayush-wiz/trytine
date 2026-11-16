// Rasterizes the slim macOS-style pointer polygon into an ASCII-art block string.
// Ported 1:1 from the original landing page's componentDidMount.
const POLY: [number, number][] = [
  [0, 0],
  [0, 16.5],
  [4.2, 12.6],
  [6.7, 18.8],
  [8.9, 17.8],
  [6.4, 11.8],
  [12.0, 11.8],
];
const X_MAX = 12.0;
const Y_MAX = 18.8;

function inside(px: number, py: number): boolean {
  let c = false;
  for (let i = 0, j = POLY.length - 1; i < POLY.length; j = i++) {
    const [xi, yi] = POLY[i];
    const [xj, yj] = POLY[j];
    if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}

export function asciiCursor(rows = 22): string {
  const cols = Math.round(0.92 * rows);
  let out = "";
  for (let r = 0; r < rows; r++) {
    const py = ((r + 0.5) / rows) * Y_MAX;
    let line = "";
    for (let col = 0; col < cols; col++) {
      const px = ((col + 0.5) / cols) * X_MAX;
      line += inside(px, py) ? "█" : " ";
    }
    out += line.replace(/\s+$/, "") + "\n";
  }
  return out;
}
