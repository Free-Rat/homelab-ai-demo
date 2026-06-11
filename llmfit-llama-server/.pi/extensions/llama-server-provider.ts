import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const baseUrl = process.env.LLAMA_SERVER_OPENAI_BASE_URL ?? "http://127.0.0.1:8080/v1";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("llama-server", {
    name: "llama-server (local)",
    baseUrl,
    apiKey: process.env.LLAMA_SERVER_API_KEY ?? "local-no-key",
    api: "openai-completions",
    models: [
      {
        id: "gemma-4-E4B-it-Q4_K_M.gguf",
        name: "Gemma 4 E4B Q4_K_M via llama-server",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 4096,
        maxTokens: 2048,
        compat: {
          supportsDeveloperRole: false,
          supportsReasoningEffort: false,
          maxTokensField: "max_tokens",
        },
      },
    ],
  });
}
