"""Compatibility patches for the nixpkgs vLLM Python closure.

The current nixpkgs combination of transformers and mistral-common can import
`ReasoningEffort` from mistral_common even though that symbol is absent from the
packaged module. vLLM reaches this path while initializing some multimodal HF
processors. Defining the missing enum is enough for the import to proceed.

The tested vLLM Transformers MoE fallback also expects text configs to expose
`top_k` or `num_experts_per_tok`. Gemma 4 exposes the same value as
`top_k_experts`, so we add read-only aliases for that config class.
"""

from enum import Enum


try:
    from mistral_common.protocol.instruct import request
except Exception:
    request = None


if request is not None and not hasattr(request, "ReasoningEffort"):

    class ReasoningEffort(str, Enum):
        low = "low"
        medium = "medium"
        high = "high"

    request.ReasoningEffort = ReasoningEffort


def _top_k_experts_alias(self):
    return getattr(self, "top_k_experts", None)


try:
    from transformers.models.gemma4.configuration_gemma4 import Gemma4TextConfig
except Exception:
    Gemma4TextConfig = None


if Gemma4TextConfig is not None:
    if not hasattr(Gemma4TextConfig, "top_k"):
        Gemma4TextConfig.top_k = property(_top_k_experts_alias)
    if not hasattr(Gemma4TextConfig, "num_experts_per_tok"):
        Gemma4TextConfig.num_experts_per_tok = property(_top_k_experts_alias)
