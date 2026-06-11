#!/usr/bin/env python3
"""Small OpenAI-compatible client for llama-server."""

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


def chat(base_url: str, model: str, prompt: str, max_tokens: int, show_thinking: bool) -> str:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    data = request_json(
        "POST",
        f"{base_url.rstrip('/')}/v1/chat/completions",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload),
    )
    message = data["choices"][0]["message"]
    content = message.get("content", "").strip()
    if content:
        return content

    reasoning = message.get("reasoning_content", "").strip()
    if show_thinking and reasoning:
        return reasoning

    if reasoning:
        return "[model returned only reasoning_content; rerun with --show-thinking to inspect it]"

    return json.dumps(data, ensure_ascii=False, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Query a local llama-server instance.")
    parser.add_argument("--base-url", default=os.getenv("LLAMA_SERVER_URL", "http://127.0.0.1:8080"))
    parser.add_argument("--model", default=os.getenv("LLAMA_SERVER_MODEL", "local-model"))
    parser.add_argument(
        "--prompt",
        default="User do not understand polish. Użyj swojej najlepszej wiedzy. Napisz jedno zdanie po polsku: co daje self-hosting LLM?",
    )
    parser.add_argument("--max-tokens", type=int, default=96)
    parser.add_argument("--health", action="store_true", help="Only verify that /v1/models responds.")
    parser.add_argument("--show-thinking", action="store_true", help="Print reasoning_content if the model returns it.")
    args = parser.parse_args()

    try:
        models = list_models(args.base_url)
        if args.health:
            print("llama-server OK")
            print("models:", ", ".join(models) if models else "(none reported)")
            return 0

        model = args.model
        if model == "local-model" and models:
            model = models[0]

        print(chat(args.base_url, model, args.prompt, args.max_tokens, args.show_thinking))
        return 0
    except requests.exceptions.RequestException as exc:
        print(f"llama-server request failed: {exc}", file=sys.stderr)
        return 1
    except (KeyError, IndexError, ValueError) as exc:
        print(f"unexpected llama-server response: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
