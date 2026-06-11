#!/usr/bin/env python3
"""Small OpenAI-compatible client for vLLM."""

import argparse
import json
import os
import sys
from typing import Any

import requests


def request_json(method: str, url: str, **kwargs: Any) -> dict[str, Any]:
    response = requests.request(method, url, timeout=kwargs.pop("timeout", 120), **kwargs)
    response.raise_for_status()
    return response.json()


def list_models(base_url: str) -> list[str]:
    data = request_json("GET", f"{base_url.rstrip('/')}/v1/models", timeout=10)
    return [model["id"] for model in data.get("data", []) if "id" in model]


def chat(base_url: str, model: str, prompt: str, max_tokens: int) -> str:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
    }
    data = request_json(
        "POST",
        f"{base_url.rstrip('/')}/v1/chat/completions",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload),
    )
    message = data["choices"][0]["message"]
    content = message.get("content", "").strip()
    return content or json.dumps(data, ensure_ascii=False, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Query a local vLLM OpenAI-compatible server.")
    parser.add_argument("--base-url", default=os.getenv("VLLM_SERVER_URL", "http://127.0.0.1:8000"))
    parser.add_argument("--model", default=os.getenv("VLLM_MODEL", "local-model"))
    parser.add_argument(
        "--prompt",
        default="Napisz jedno zdanie po polsku: kiedy warto użyć vLLM zamiast llama.cpp?",
    )
    parser.add_argument("--max-tokens", type=int, default=96)
    parser.add_argument("--health", action="store_true", help="Only verify that /v1/models responds.")
    args = parser.parse_args()

    try:
        models = list_models(args.base_url)
        if args.health:
            print("vLLM OK")
            print("models:", ", ".join(models) if models else "(none reported)")
            return 0

        model = args.model
        if model == "local-model" and models:
            model = models[0]

        print(chat(args.base_url, model, args.prompt, args.max_tokens))
        return 0
    except requests.exceptions.RequestException as exc:
        print(f"vLLM request failed: {exc}", file=sys.stderr)
        return 1
    except (KeyError, IndexError, ValueError) as exc:
        print(f"unexpected vLLM response: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
