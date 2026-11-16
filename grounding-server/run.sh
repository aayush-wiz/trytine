#!/bin/zsh
# Start the grounding FastAPI service on :8799.
# Reads OPENROUTER_API_KEY from ClickyMine's Info.plist (if built as an app) so litellm's
# openrouter/ models work, falling back to whatever is already in the environment.
cd "$(dirname "$0")" || exit 1

PLIST="$(dirname "$0")/../macos-app/.build/release/ClickyMine.app/Contents/Info.plist"
if [ -z "$OPENROUTER_API_KEY" ] && [ -f "$PLIST" ]; then
  export OPENROUTER_API_KEY="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:OPENROUTER_API_KEY' "$PLIST" 2>/dev/null)"
fi
: "${GROUNDING_MODEL:=openrouter/anthropic/claude-sonnet-4.6}"
export GROUNDING_MODEL
echo "grounding model: $GROUNDING_MODEL  (key: ${OPENROUTER_API_KEY:0:14}...)"
exec python3 -m uvicorn server:app --host 127.0.0.1 --port 8799 --log-level warning
