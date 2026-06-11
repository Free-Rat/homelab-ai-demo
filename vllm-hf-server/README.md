# vLLM + Hugging Face

Run a Hugging Face transformer checkpoint with vLLM's OpenAI-compatible server. This is the direct Hugging Face alternative to the GGUF-based `../llmfit-llama-server` demo.

## Quick Start

```bash
cd demo/vllm-hf-server
nix develop
./run-server.sh --check
./run-server.sh --serve
```

In a second terminal:

```bash
cd demo/vllm-hf-server
nix develop
./run-server.sh --health
./run-server.sh --request
```

If the model is gated, authenticate first:

```bash
hf auth login
```

## Configuration

- Default model: `google/gemma-4-E4B-it`
- Served model name: `gemma`
- Server URL: `http://127.0.0.1:8000`
- OpenAI-compatible endpoint: `/v1/chat/completions`
- Context size: `4096`
- Tool calling: disabled by default for a plain, reliable chat server

Use another Hugging Face model or local snapshot:

```bash
./run-server.sh --model google/gemma-4-E4B-it --serve
./run-server.sh --model ~/.cache/huggingface/hub/models--org--model/snapshots/<hash> --serve
```

Run a one-command smoke test:

```bash
./run-server.sh --smoke-test
```

## Useful Environment Variables

```bash
VLLM_SERVER_PORT=8001 ./run-server.sh --serve
VLLM_MAX_MODEL_LEN=2048 ./run-server.sh --serve
VLLM_GPU_MEMORY_UTILIZATION=0.80 ./run-server.sh --serve
VLLM_DTYPE=half ./run-server.sh --serve
VLLM_SERVED_MODEL_NAME=gemma-local ./run-server.sh --serve
```

Enable vLLM's automatic tool choice only when testing models and parsers that support it:

```bash
VLLM_ENABLE_AUTO_TOOL_CHOICE=1 VLLM_TOOL_CALL_PARSER=<parser> ./run-server.sh --serve
```

Stop a running server on the configured port:

```bash
./run-server.sh --stop
```

## Notes

- `nix develop` provides Python, the Hugging Face CLI, ROCm runtime libraries, `curl`, `jq`, Node.js, and `vllm` from `nixpkgs`.
- `./run-server.sh --check` validates the Python client and shows the resolved model.
- `./run-server.sh --request` sends one request to an already running server.
- `compat/sitecustomize.py` is added to `PYTHONPATH` to work around a current `nixpkgs` `mistral-common` import mismatch.
- If vLLM startup fails on ROCm, try lowering `VLLM_MAX_MODEL_LEN` or `VLLM_GPU_MEMORY_UTILIZATION`, or use the GGUF demo in `../llmfit-llama-server`.

## Pi

Pi can use the same vLLM server through `.pi/extensions/vllm-provider.ts`:

```bash
./run-server.sh --pi-smoke-test
./run-server.sh --pi-tool-test
./run-server.sh --pi
```

Plain chat is the reliable baseline. Tool behavior depends on the checkpoint, chat template, and selected vLLM tool parser.

## Files

- `README.md` explains how to recreate and run the demo.
- `flake.nix` defines the Nix development shell with vLLM, Python, Hugging Face tooling, ROCm libraries, and Node.js.
- `flake.lock` pins the Nix inputs so the shell is reproducible.
- `run-server.sh` manages vLLM startup, health checks, smoke tests, and Pi commands.
- `client.py` is a minimal OpenAI-compatible client used for health checks and example requests.
- `compat/sitecustomize.py` patches known package compatibility gaps needed by this vLLM environment.
- `.pi/extensions/vllm-provider.ts` registers the local vLLM endpoint as a Pi provider.
