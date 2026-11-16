# Tine macOS app (codename: ClickyMine)

The macOS app behind [Tine](../README.md) — a from-scratch, on-screen AI buddy. `ClickyMine`
is the Swift module/target name (SwiftPM has no per-package namespacing, so it lives on in
`Package.swift` and imports); the shipped product is called **Tine**.

A companion cursor lives on a transparent, click-through overlay above every window. You ask
a question, it screenshots your screen, sends it to an LLM (vision) over OpenRouter, then
**speaks** the answer and **glides the cursor to point** at the right spot. Your real cursor
keeps working normally underneath.

## What it does today (MVP)
- ⌃⌥Space (Control+Option+Space) or the menu-bar ▲ → ask a question
- Captures the main display (downscaled 1280px / JPEG 80%, the Clicky recipe)
- The model returns `{say, x, y, point}` → speaks via system TTS + points the cursor
- Pure pointing (no auto-clicking yet) — safe, like a tutor's hand

## Run it
```bash
git clone https://github.com/hritvikgupta/trytine.git
cd trytine/macos-app

export OPENROUTER_API_KEY=sk-or-...
swift run
```
First launch macOS will ask for **Screen Recording** and **Accessibility** permissions
(System Settings → Privacy & Security). Grant both, then relaunch.

See the [root README](../README.md) for the full env var reference (`LLM_MODEL`, `CU_MODEL`,
`OPENROUTER_BASE_URL`, …) and the rest of the monorepo (landing page, grounding server).

## Architecture
The code is organized into layers (under `Sources/ClickyMine/`), separating the app shell,
the agent's reasoning, external integrations, OS-level wrappers, and the UI:

```
Sources/ClickyMine/
├── App/        App shell & orchestration (entry point)
│   └── main.swift          Menu-bar app, global hotkey, window wiring, agent runners
├── Agent/      Core business logic (the "brain")
│   └── Agent.swift         Native ReAct loop: reason → tool → observe → repeat
├── Libs/       External integrations
│   └── Claude.swift        OpenRouter/LLM client (chat completions, vision)
├── System/     macOS platform wrappers (Accessibility, input, capture, speech)
│   ├── Inspector.swift     AXUIElement: clickable elements, focused field, hit-testing
│   ├── Clicker.swift       Synthetic CGEvent input: click, type, hotkey, scroll
│   ├── ScreenCapture.swift Main-display screenshot → resize → base64 JPEG
│   └── Voice.swift         Speech recognition (STT)
└── UI/         Presentation layer
    ├── Island.swift        Notch-native Dynamic Island (NotchDrop port)
    ├── Panes.swift         Activity + Chat panes
    ├── Sidebar.swift       Floating, draggable Copilot-style chat sidebar
    └── Overlay.swift       Transparent click-through triangle companion cursor
```

> Swift has no per-folder namespacing — every file in the target shares one module, so these
> folders are purely organizational and SwiftPM compiles them all without any `Package.swift`
> changes.

## Next steps (turn pointing into acting)
1. **Voice input** — swap the text prompt for SFSpeechRecognizer / AssemblyAI push-to-talk.
2. **Real clicking (agent mode)** — fire a `CGEvent` left-click at the same coords the triangle points to.
3. **Accessibility targeting** — use `AXUIElement` to click named UI elements instead of raw pixels.
4. **Streaming** — stream Claude + TTS so replies feel instant.
