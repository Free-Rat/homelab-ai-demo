#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${OLLAMA_MODEL:-gemma4:e4b}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
COMMANDS_URL="${DEMO_COMMANDS_URL:-}"

usage() {
  cat <<'EOF'
Usage: ./demo.sh [--commands] [--run] [--opencode]

Options:
  --commands   Print the command list for the recording.
  --run        Start Ollama if needed, pull the model, and run a smoke test.
  --opencode   Launch OpenCode using the local Ollama provider config.

Environment:
  OLLAMA_MODEL=gemma4:e4b
  OLLAMA_HOST=127.0.0.1:11434
  DEMO_COMMANDS_URL=https://.../commands.txt
EOF
}

print_commands() {
  if [ -n "$COMMANDS_URL" ]; then
    curl -fsSL "$COMMANDS_URL"
  else
    cat "$SCRIPT_DIR/commands.txt"
  fi
}

wait_for_ollama() {
  for _ in $(seq 1 30); do
    if curl -fsS "http://$OLLAMA_HOST/api/tags" >/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "Ollama did not become ready on $OLLAMA_HOST" >&2
  return 1
}

ensure_ollama() {
  if curl -fsS "http://$OLLAMA_HOST/api/tags" >/dev/null; then
    return 0
  fi

  echo "Starting ollama serve on $OLLAMA_HOST"
  OLLAMA_HOST="$OLLAMA_HOST" ollama serve >/tmp/opencode-ollama-demo.log 2>&1 &
  wait_for_ollama
}

run_demo() {
  command -v ollama >/dev/null || { echo "ollama is missing. Run: nix develop" >&2; exit 1; }
  command -v curl >/dev/null || { echo "curl is missing. Run: nix develop" >&2; exit 1; }

  ensure_ollama
  ollama pull "$MODEL"
  curl -fsS "http://$OLLAMA_HOST/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say: local AI działa.\"}],\"max_tokens\":32,\"temperature\":0}" \
    | jq -r '.choices[0].message.content'
}

run_opencode() {
  if ! command -v opencode >/dev/null; then
    echo "OpenCode is missing. Run this demo through: nix develop" >&2
    exit 1
  fi

  export OPENCODE_CONFIG="${OPENCODE_CONFIG:-$SCRIPT_DIR/opencode.json}"
  ensure_ollama
  echo "OpenCode config: $OPENCODE_CONFIG"
  echo "Recommended model: ollama / Gemma 4 E4B (Ollama)"
  exec opencode
}

case "${1:---commands}" in
  --commands) print_commands ;;
  --run) run_demo ;;
  --opencode) run_opencode ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
