#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_PRESET="${LLAMA_MODEL_PRESET:-gemma}"
GEMMA_MODEL_PATH="${GEMMA_MODEL_PATH:-$SCRIPT_DIR/models/gemma4-e4b/gemma-4-E4B-it-Q4_K_M.gguf}"
HOST="${LLAMA_SERVER_HOST:-0.0.0.0}"
PORT="${LLAMA_SERVER_PORT:-8080}"
CLIENT_BASE_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:$PORT}"
CTX_SIZE="${LLAMA_CTX_SIZE:-4096}"
BATCH_SIZE="${LLAMA_BATCH_SIZE:-512}"
if [ -n "${LLAMA_GPU_LAYERS:-}" ]; then
  GPU_LAYERS="$LLAMA_GPU_LAYERS"
elif [ "$MODEL_PRESET" = "gemma" ]; then
  GPU_LAYERS="99"
else
  GPU_LAYERS=""
fi
PROMPT="${LLAMA_DEMO_PROMPT:-User do not understand polish. Użyj swojej najlepszej wiedzy. Napisz jedno zdanie po polsku: co daje self-hosting LLM?}"
MAX_TOKENS="${LLAMA_DEMO_MAX_TOKENS:-96}"

model_path_for() {
  case "$1" in
    gemma) echo "$GEMMA_MODEL_PATH" ;;
    *) echo "$1" ;;
  esac
}

MODEL_PATH="${MODEL_PATH:-$(model_path_for "$MODEL_PRESET")}"

usage() {
  cat <<EOF
Usage: ./run-server.sh [--check] [--serve] [--request] [--smoke-test] [--opencode] [--pi] [--pi-smoke-test] [--pi-tool-test] [--status] [--stop]

Options:
  --check       Validate tools, model file, and Python client syntax.
  --llmfit-help Create .venv if needed and verify llmfit is installed.
  --serve       Start llama-server.
  --request     Send one request to an already running llama-server.
  --smoke-test  Start llama-server, send one request, then stop it.
  --opencode    Launch OpenCode configured to use this llama-server.
  --pi          Launch pi configured to use this llama-server.
  --pi-smoke-test Send one plain non-interactive pi request to llama-server.
  --pi-tool-test Try one pi tool-calling request against llama-server.
  --status      Show whether something is listening on LLAMA_SERVER_PORT.
  --stop        Stop the process listening on LLAMA_SERVER_PORT.
  --model NAME  Select model preset: gemma or a direct .gguf path.

Environment:
  MODEL_PATH=$MODEL_PATH
  GEMMA_MODEL_PATH=$GEMMA_MODEL_PATH
  LLAMA_GPU_LAYERS=${GPU_LAYERS:-auto-fit}
  LLAMA_SERVER_HOST=$HOST
  LLAMA_SERVER_PORT=$PORT
  LLAMA_SERVER_URL=$CLIENT_BASE_URL
  LLAMA_DEMO_PROMPT=$PROMPT
  LLAMA_HIP_VISIBLE_DEVICES=${LLAMA_HIP_VISIBLE_DEVICES:-0}
  LLAMA_ROCR_VISIBLE_DEVICES=${LLAMA_ROCR_VISIBLE_DEVICES:-0}
EOF
}

pi_cmd() {
  if command -v pi >/dev/null; then
    printf '%s\0' pi
  else
    command -v npx >/dev/null || { echo "pi is missing and npx is unavailable. Enter nix develop first." >&2; return 1; }
    printf '%s\0' npx --yes @earendil-works/pi-coding-agent@0.77.0
  fi
}

port_pid() {
  local line
  line="$(ss -ltnp "sport = :$PORT" 2>/dev/null | grep 'pid=' || true)"
  if [[ "$line" =~ pid=([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

status_server() {
  local pid
  pid="$(port_pid)"
  if [ -z "$pid" ]; then
    echo "No process is listening on port $PORT."
    return 1
  fi

  echo "Port $PORT is used by PID $pid:"
  tr '\0' ' ' <"/proc/$pid/cmdline" || true
  echo
}

stop_server() {
  local pid
  pid="$(port_pid)"
  if [ -z "$pid" ]; then
    echo "No process is listening on port $PORT."
    return 0
  fi

  echo "Stopping PID $pid on port $PORT."
  kill "$pid"
}

install_llmfit() {
  if [ ! -x "$SCRIPT_DIR/.venv/bin/llmfit" ]; then
    python3 -m venv "$SCRIPT_DIR/.venv"
    "$SCRIPT_DIR/.venv/bin/python" -m pip install --upgrade pip >/dev/null
    "$SCRIPT_DIR/.venv/bin/python" -m pip install llmfit >/dev/null
  fi
}

check_demo() {
  command -v llama-server >/dev/null || { echo "llama-server is missing. Run: nix develop .#rocm" >&2; exit 1; }
  python3 -m py_compile "$SCRIPT_DIR/client.py"

  echo "model preset: $MODEL_PRESET"
  if [ -f "$MODEL_PATH" ]; then
    echo "model OK: $MODEL_PATH"
  else
    echo "model missing: $MODEL_PATH" >&2
    echo "Set MODEL_PATH=/path/to/model.gguf before --serve." >&2
  fi
}

serve() {
  command -v llama-server >/dev/null || { echo "llama-server is missing. Run: nix develop .#rocm" >&2; exit 1; }
  [ -f "$MODEL_PATH" ] || { echo "model missing: $MODEL_PATH" >&2; exit 1; }

  if status_server >/dev/null; then
    status_server >&2
    echo "Use --request or --opencode to use the running server, --stop to stop it, or LLAMA_SERVER_PORT=<port> --serve to start another one." >&2
    exit 1
  fi

  # Prefer the first visible ROCm device unless the caller selects another one.
  export HIP_VISIBLE_DEVICES="${LLAMA_HIP_VISIBLE_DEVICES:-0}"
  export ROCR_VISIBLE_DEVICES="${LLAMA_ROCR_VISIBLE_DEVICES:-0}"
  export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"

  echo "Starting llama-server on $HOST:$PORT with HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES=$ROCR_VISIBLE_DEVICES"
  if [ -n "$GPU_LAYERS" ]; then
    echo "GPU layers: $GPU_LAYERS"
  else
    echo "GPU layers: auto-fit"
  fi

  local gpu_layer_args=()
  if [ -n "$GPU_LAYERS" ]; then
    gpu_layer_args=(-ngl "$GPU_LAYERS")
  fi

  exec llama-server \
    -m "$MODEL_PATH" \
    --ctx-size "$CTX_SIZE" \
    --batch-size "$BATCH_SIZE" \
    -fa on \
    "${gpu_layer_args[@]}" \
    --host "$HOST" \
    --port "$PORT"
}

wait_for_server() {
  for _ in $(seq 1 180); do
    if python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "llama-server did not become ready at $CLIENT_BASE_URL" >&2
  return 1
}

request_server() {
  echo "Request: $PROMPT"
  echo "Response:"
  python3 "$SCRIPT_DIR/client.py" \
    --base-url "$CLIENT_BASE_URL" \
    --prompt "$PROMPT" \
    --max-tokens "$MAX_TOKENS"
}

run_opencode() {
  command -v opencode >/dev/null || { echo "opencode is missing. Run this demo through nix develop, or use the opencode-ollama demo." >&2; exit 1; }
  wait_for_server

  export OPENCODE_CONFIG="${OPENCODE_CONFIG:-$SCRIPT_DIR/opencode.json}"
  echo "OpenCode config: $OPENCODE_CONFIG"
  echo "Provider URL: $CLIENT_BASE_URL/v1"
  echo "For the most reliable coding-agent flow, compare with ../opencode-ollama using gemma4:e4b."
  exec opencode
}

run_pi() {
  wait_for_server

  local model_id
  model_id="$(python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health | sed -n 's/^models: //p' | cut -d, -f1)"
  if [ -z "$model_id" ] || [ "$model_id" = "(none reported)" ]; then
    model_id="$(basename "$MODEL_PATH")"
  fi

  export LLAMA_SERVER_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export LLAMA_SERVER_API_KEY="${LLAMA_SERVER_API_KEY:-local-no-key}"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  echo "Pi provider URL: $LLAMA_SERVER_OPENAI_BASE_URL"
  echo "Pi model: llama-server/$model_id"
  exec "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/llama-server-provider.ts" \
    --model "llama-server/$model_id"
}

pi_smoke_test() {
  wait_for_server

  local model_id
  model_id="$(python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health | sed -n 's/^models: //p' | cut -d, -f1)"
  if [ -z "$model_id" ] || [ "$model_id" = "(none reported)" ]; then
    model_id="$(basename "$MODEL_PATH")"
  fi

  export LLAMA_SERVER_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export LLAMA_SERVER_API_KEY="${LLAMA_SERVER_API_KEY:-local-no-key}"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/llama-server-provider.ts" \
    --model "llama-server/$model_id" \
    --thinking off \
    --no-session \
    --no-tools \
    -p 'Odpowiedz dokładnie jednym słowem: DZIALA'
}

pi_tool_test() {
  wait_for_server

  local model_id
  model_id="$(python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health | sed -n 's/^models: //p' | cut -d, -f1)"
  if [ -z "$model_id" ] || [ "$model_id" = "(none reported)" ]; then
    model_id="$(basename "$MODEL_PATH")"
  fi

  export LLAMA_SERVER_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export LLAMA_SERVER_API_KEY="${LLAMA_SERVER_API_KEY:-local-no-key}"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  echo "Experimental: this tests Pi tool calling. Current GGUF models may emit garbage tokens or ignore tools."
  "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/llama-server-provider.ts" \
    --model "llama-server/$model_id" \
    --thinking off \
    --no-session \
    --tools bash,ls \
    -p 'Run `ls -la` and return only the command output.'
}

smoke_test() {
  local log_file="${LLAMA_SERVER_LOG:-/tmp/homelab-llama-server-demo.log}"

  if python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
    echo "Using already running llama-server at $CLIENT_BASE_URL"
    request_server
    return 0
  fi

  serve >"$log_file" 2>&1 &
  SMOKE_SERVER_PID=$!

  cleanup() {
    kill "$SMOKE_SERVER_PID" 2>/dev/null || true
    wait "$SMOKE_SERVER_PID" 2>/dev/null || true
  }
  trap cleanup EXIT

  for _ in $(seq 1 180); do
    if python3 "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
      request_server
      cleanup
      trap - EXIT
      return 0
    fi

    if ! kill -0 "$SMOKE_SERVER_PID" 2>/dev/null; then
      echo "llama-server exited early; log follows:" >&2
      sed -n '1,160p' "$log_file" >&2
      trap - EXIT
      return 1
    fi

    sleep 2
  done

  echo "llama-server did not become ready at $CLIENT_BASE_URL; log follows:" >&2
  sed -n '1,160p' "$log_file" >&2
  cleanup
  trap - EXIT
  return 1
}

case "${1:---check}" in
  --model)
    shift
    [ $# -gt 0 ] || { echo "--model requires: gemma or /path/to/model.gguf" >&2; exit 2; }
    export LLAMA_MODEL_PRESET="$1"
    export MODEL_PATH="$(model_path_for "$1")"
    shift
    exec "$0" "${@:---check}"
    ;;
  --gemma)
    shift
    export LLAMA_MODEL_PRESET="gemma"
    export MODEL_PATH="$GEMMA_MODEL_PATH"
    exec "$0" "${@:---check}"
    ;;
  --check) check_demo ;;
  --llmfit-help)
    install_llmfit
    if "$SCRIPT_DIR/.venv/bin/llmfit" --help; then
      exit 0
    fi
    "$SCRIPT_DIR/.venv/bin/python" - <<'PY'
import importlib.metadata

print("llmfit installed:", importlib.metadata.version("llmfit"))
print("llmfit CLI is a binary wheel; on NixOS run it inside an FHS/nix-ld environment.")
PY
    ;;
  --serve) serve ;;
  --request) wait_for_server; request_server ;;
  --smoke-test) smoke_test ;;
  --opencode) run_opencode ;;
  --pi) run_pi ;;
  --pi-smoke-test) pi_smoke_test ;;
  --pi-tool-test) pi_tool_test ;;
  --status) status_server ;;
  --stop) stop_server ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
