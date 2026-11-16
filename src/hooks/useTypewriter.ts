import { useEffect, useState } from "react";

/**
 * Cycles through `phrases`, typing and deleting each one — the command-bar effect in the hero.
 * Returns the current visible substring.
 */
export function useTypewriter(
  phrases: string[],
  opts: { typeMs?: number; deleteMs?: number; holdMs?: number; gapMs?: number; startMs?: number } = {},
): string {
  const { typeMs = 55, deleteMs = 28, holdMs = 1400, gapMs = 400, startMs = 700 } = opts;
  const [text, setText] = useState("");

  useEffect(() => {
    let pi = 0;
    let ci = 0;
    let deleting = false;
    let timer: ReturnType<typeof setTimeout>;

    const step = () => {
      const word = phrases[pi];
      if (!deleting) {
        ci++;
        setText(word.slice(0, ci));
        if (ci >= word.length) {
          deleting = true;
          timer = setTimeout(step, holdMs);
          return;
        }
        timer = setTimeout(step, typeMs);
      } else {
        ci--;
        setText(word.slice(0, ci));
        if (ci <= 0) {
          deleting = false;
          pi = (pi + 1) % phrases.length;
          timer = setTimeout(step, gapMs);
          return;
        }
        timer = setTimeout(step, deleteMs);
      }
    };

    timer = setTimeout(step, startMs);
    return () => clearTimeout(timer);
  }, [phrases, typeMs, deleteMs, holdMs, gapMs, startMs]);

  return text;
}
