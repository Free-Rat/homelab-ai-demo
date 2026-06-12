# llama-server + GGUF

Run a local OpenAI-compatible server with `llama-server` and a Gemma GGUF model. This is the smallest moving-parts path for serving a local model over HTTP.

## Quick Start

```bash
cd demo/llmfit-llama-server
nix develop
./run-server.sh --check
```

Download or convert a GGUF export of `google/gemma-4-E4B-it`, then place it at the default path:

```bash
mkdir -p ./models/gemma4-e4b
cp /path/to/gemma-4-E4B-it-Q4_K_M.gguf ./models/gemma4-e4b/
```

If the model is gated, authenticate first:

```bash
hf auth login
```

If your GGUF file has a different name or location, pass it explicitly:

```bash
./run-server.sh --model /path/to/model.gguf --serve
```

Start the server:

```bash
./run-server.sh --serve
```

In a second terminal:

```bash
cd demo/llmfit-llama-server
nix develop
python3 client.py --health
python3 client.py
```

For a one-command check, run:

```bash
./run-server.sh --smoke-test
```

## Configuration

- Default model path: `./models/gemma4-e4b/gemma-4-E4B-it-Q4_K_M.gguf`
- Server URL: `http://127.0.0.1:8080`
- OpenAI-compatible endpoint: `/v1/chat/completions`
- Context size: `4096`
- GPU layers: `99` by default for the Gemma preset

Change the port:

```bash
LLAMA_SERVER_PORT=8081 ./run-server.sh --serve
```

Stop a running server on the configured port:

```bash
./run-server.sh --stop
```

## OpenCode

`opencode.json` points OpenCode at the local `llama-server` API. Start the server first, then run:

```bash
./run-server.sh --opencode
```

For coding-agent demos, `../opencode-ollama` is usually more reliable because Ollama supplies the model template and runtime defaults. Use this demo when you specifically want to show raw `llama-server` hosting.

## Pi

Pi can use the same server through the local extension in `.pi/extensions/llama-server-provider.ts`:

```bash
./run-server.sh --pi-smoke-test
./run-server.sh --pi-tool-test
./run-server.sh --pi
```

## Notes

- `nix develop` provides `llama-server`, Python, `requests`, and the Hugging Face CLI.
- `./run-server.sh --check` validates tools and shows whether the default model file exists.
- `./run-server.sh --request` sends one request to an already running server.
- `MODEL_PATH=/path/to/model.gguf ./run-server.sh --serve` is equivalent to `--model /path/to/model.gguf --serve`.
- On ROCm hosts, override device selection with `LLAMA_HIP_VISIBLE_DEVICES` and `LLAMA_ROCR_VISIBLE_DEVICES` if needed.

## Files

- `README.md` explains how to recreate and run the demo.
- `flake.nix` defines the Nix development shell with `llama-server`, Python, Hugging Face tooling, OpenCode, and Node.js.
- `flake.lock` pins the Nix inputs so the shell is reproducible.
- `run-server.sh` manages server startup, health checks, smoke tests, OpenCode, and Pi commands.
- `client.py` is a minimal OpenAI-compatible client used for health checks and example requests.
- `opencode.json` configures OpenCode to use the local `llama-server` endpoint.
- `.pi/extensions/llama-server-provider.ts` registers the local `llama-server` endpoint as a Pi provider.
