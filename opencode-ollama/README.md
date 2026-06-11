# OpenCode + Ollama

Run a local coding agent with a self-hosted Ollama model. Nix provides the tools, Ollama serves `gemma4:e4b`, and OpenCode connects through Ollama's OpenAI-compatible API.

## Quick Start

```bash
cd demo/opencode-ollama
nix develop
./demo.sh --run
./demo.sh --opencode
```

`./demo.sh --run` starts Ollama if needed, pulls `gemma4:e4b`, and sends a smoke-test request. `./demo.sh --opencode` opens OpenCode with `opencode.json` already pointed at `http://127.0.0.1:11434/v1`.

## One-Shot Install

After publishing this directory, a reader can recreate the demo on a fresh machine with Nix installed:

```bash
export DEMO_BASE_URL="https://raw.githubusercontent.com/<user>/<repo>/<branch>/demo/opencode-ollama"
curl -fsSL "$DEMO_BASE_URL/commands.txt" | bash
```

## Configuration

- Default model: `gemma4:e4b`
- Server URL: `http://127.0.0.1:11434`
- OpenCode config: `opencode.json`

Override the model only if you know it is available in Ollama:

```bash
OLLAMA_MODEL=gemma4:e4b ./demo.sh --run
```

## Files

- `README.md` explains how to recreate and run the demo.
- `flake.nix` defines the Nix development shell with Ollama, OpenCode, `curl`, and `jq`.
- `flake.lock` pins the Nix inputs so the shell is reproducible.
- `demo.sh` starts or checks Ollama, pulls the model, runs a smoke test, and launches OpenCode.
- `opencode.json` configures OpenCode to use Ollama through `http://127.0.0.1:11434/v1`.
- `commands.txt` contains the downloadable one-shot setup commands for a fresh machine.
