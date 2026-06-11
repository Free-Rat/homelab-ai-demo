import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const baseUrl = process.env.VLLM_OPENAI_BASE_URL ?? "http://127.0.0.1:8000/v1";
const modelId = process.env.VLLM_PI_MODEL_ID ?? "gemma";
const modelName = process.env.VLLM_PI_MODEL_NAME ?? `${modelId} via vLLM`;
const contextWindow = Number(process.env.VLLM_PI_CONTEXT_WINDOW ?? "4096");
const maxTokens = Number(process.env.VLLM_PI_MAX_TOKENS ?? "2048");

export default function (pi: ExtensionAPI) {
  pi.registerProvider("vllm", {
    name: "vLLM (local)",
    baseUrl,
    apiKey: process.env.VLLM_API_KEY ?? "local-no-key",
    api: "openai-completions",
    models: [
      {
        id: modelId,
        name: modelName,
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow,
        maxTokens,
        compat: {
          supportsDeveloperRole: false,
          supportsReasoningEffort: false,
          maxTokensField: "max_tokens",
        },
      },
    ],
  });
}
