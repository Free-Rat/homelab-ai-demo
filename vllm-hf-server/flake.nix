{
  description = "vLLM Hugging Face safetensors demo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            rocmSupport = true;
          };
        };

        python = pkgs.python3.withPackages (ps: with ps; [
          huggingface-hub
          requests
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            git
            jq
            nodejs_22
            python
            rocmPackages.clr
            vllm
          ];

          shellHook = ''
            export VLLM_SERVER_HOST="''${VLLM_SERVER_HOST:-0.0.0.0}"
            export VLLM_SERVER_PORT="''${VLLM_SERVER_PORT:-8000}"
            export VLLM_SERVER_URL="''${VLLM_SERVER_URL:-http://127.0.0.1:$VLLM_SERVER_PORT}"
            export HF_HOME="''${HF_HOME:-$HOME/.cache/huggingface}"
            export HIP_VISIBLE_DEVICES="''${HIP_VISIBLE_DEVICES:-0}"
            export ROCR_VISIBLE_DEVICES="''${ROCR_VISIBLE_DEVICES:-0}"
            export HSA_OVERRIDE_GFX_VERSION="''${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"
            export PYTHONPATH="$PWD/compat''${PYTHONPATH:+:$PYTHONPATH}"

            echo "vLLM Hugging Face demo"
            echo "  ./run-server.sh --serve"
            echo "  ./run-server.sh --health"
            echo "  ./run-server.sh --request"
            echo "  ./run-server.sh --pi-smoke-test"
          '';
        };
      }
    );
}
