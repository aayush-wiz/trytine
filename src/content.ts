// All copy + data for the landing page, in one place so it's easy to edit.

export const HERO_PHRASES = [
  "reply to Sarah and book a room",
  "summarize this thread for me",
  "fill out this signup form",
];

export const TICKER = ["Lives beside your cursor", "Sees your screen", "Acts on your say-so"];

export type Mode = {
  id: 1 | 2 | 3;
  kicker: string;
  title: string;
  body: string;
  panelTitle: string;
};

export const MODES: Mode[] = [
  {
    id: 1,
    kicker: "01 · Watch",
    title: "It observes.",
    body: "Tine sits beside your cursor and reads the active app, your selection, and your recent moves — no prompts, no copy-paste, no context to re-explain.",
    panelTitle: "Watch",
  },
  {
    id: 2,
    kicker: "02 · Assist",
    title: "It suggests.",
    body: "When it spots something it can do, it offers — a draft, a fill, a next step — right where you are. One keystroke to accept, one to wave it off.",
    panelTitle: "Assist",
  },
  {
    id: 3,
    kicker: "03 · Take over",
    title: "It acts.",
    body: "Hand it a goal and Tine drives the cursor itself — clicking through multi-step work while you watch. Grab the mouse to pause it instantly.",
    panelTitle: "Take over",
  },
];

export type Feature = { n: string; title: string; body: string };

export const FEATURES: Feature[] = [
  { n: "01", title: "Reads your context.", body: "Watches the active app, your selection, and recent actions — so it always knows what you're trying to do." },
  { n: "02", title: "Drafts in place.", body: "Replies, messages, and docs written right where your cursor is — no window-hopping, no copy-paste." },
  { n: "03", title: "Fills the busywork.", body: "Forms, fields, and the same five clicks you do every day — handled while you move on to something better." },
  { n: "04", title: "Runs multi-step tasks.", body: "Give it a goal and it clicks all the way through — across apps, tabs, and screens — until it's done." },
  { n: "05", title: "Learns your patterns.", body: "Adapts to how you actually work — your apps, your phrasing, your shortcuts — and it all stays on your machine." },
  { n: "06", title: "Hands control back.", body: "Pause, correct, or take the wheel anytime — just touch the mouse and Tine steps aside." },
];

export const CONTROL_POINTS = [
  "Runs on-device by default",
  "Every takeover needs your ok",
  "Watches only what you allow",
  "One hotkey kill switch",
  "Nothing leaves without consent",
  "See exactly what it saw",
];

export const CONTROL_STATS = [
  { big: "⌘⇧␣", label: "to summon", brand: false },
  { big: "on-device", label: "by default", brand: true },
  { big: "100%", label: "you approve", brand: false },
  { big: "3", label: "modes", brand: false },
];

// ASCII texture used as a faint background in the colored sections.
export const ASCII_TEXTURE = `  perch ~ watching ·········· on it      ⌘⇧␣   01001     ░▒▓    → reply to sarah    book a room   ⏎   0110
→ reply to sarah    book a room      ░▒▓     ⏎    0110     perch ~ drafting ············· ✓     ◇   10010
  $ perch ~ drafting ············· ✓        ◇   10010     ██   summarize this thread for me   →   ░░░░░  ⏎
██  summarize this thread for me      →    ░░░░░   ⏎     perch ~ acting ·········· filing expenses ✓   00111
  perch ~ acting ·········· filing expenses ✓   00111     → fill out signup form   ⌘⇧␣   01001110    ◇
→ fill out signup form     ⌘⇧␣     01001110     ◇     $ perch ~ watching ·········· on it    ▟▙   ⏎  101
  $ perch ~ watching ·········· on it      ▟▙    ⏎     ░▒▓   matched to categories ✓   → next step  10101
░▒▓   matched to categories ✓      → next step   10101     perch ~ on it ··········· drafting a reply   011
  perch ~ on it ··········· drafting a reply    011     → across mail · calendar · browser   ⌘⇧␣   0010
→ across mail · calendar · browser      ⌘⇧␣   0010     $ perch ~ acting ·········· uploaded 6 receipts ✓
  $ perch ~ acting ·········· uploaded 6 receipts ✓     ██   summarize this thread for me   ░░░░░   ⏎  101
██   summarize this thread for me     ░░░░░    ⏎  101     perch ~ watching ·········· on it    ⌘⇧␣   01001`;
