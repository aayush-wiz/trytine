# Contributing to Tine

Thanks for taking a look — Tine is a monorepo with three independent pieces. Pick whichever one your change touches; you only need to set up that piece, not all three.

| Piece | Path | Stack |
|---|---|---|
| macOS app | [`macos-app/`](macos-app) | Swift 6, SwiftPM |
| Landing page | [`src/`](src) / [`js/`](js) | Vite + React + TypeScript (and a no-build JS copy) |
| Grounding server | [`grounding-server/`](grounding-server) | Python + FastAPI |

See the [README](README.md) for what each piece does and how to run it.

## Development setup

```bash
git clone https://github.com/hritvikgupta/trytine.git
cd trytine
```

- **macOS app:** `cd macos-app && export OPENROUTER_API_KEY=sk-or-... && swift run`
- **Landing page:** `npm install && npm run dev`
- **Grounding server:** `cd grounding-server && pip install -r requirements.txt && ./run.sh`

## Making a change

1. Fork the repo and create a branch off `main`: `git checkout -b your-change`.
2. Keep changes scoped to one of the three pieces where possible — it makes review faster.
3. For the macOS app, test the actual behavior (screen capture, pointing, hotkeys) on-device before opening a PR; there's no CI running the app yet.
4. For the landing page, run `npm run build` to make sure the type-check and production build pass.
5. Write a clear commit message describing *why*, not just *what*.
6. Open a PR against `main` with a short description of the change and, if it's a visual change, a screenshot or clip.

## Reporting bugs / requesting features

Open a [GitHub issue](https://github.com/hritvikgupta/trytine/issues). For bugs, include:
- macOS version and whether you're running via `swift run` or a built `.app`
- Steps to reproduce
- What you expected vs. what happened

## Code style

- Swift: follow the existing layering in `macos-app/README.md` (`App/`, `Agent/`, `Libs/`, `System/`, `UI/`) — put new files in the folder that matches their role.
- TypeScript/React: components live in `src/components/`, copy/data lives in `src/content.ts` — keep content and presentation separate.
- No enforced linter yet — match the formatting of the surrounding code.

## License

By contributing, you agree your contributions will be licensed under the project's [PolyForm Noncommercial License 1.0.0](LICENSE).
