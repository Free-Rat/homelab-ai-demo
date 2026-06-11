{
  description = "llmfit + llama-server demo client";

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
        llama-cpp-rocm = pkgs.llama-cpp.override { rocmSupport = true; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            jq
            nodejs_22
            python
            python3Packages.pip
            llama-cpp-rocm
            opencode
            rocmPackages.clr
          ];

          shellHook = ''
            export HIP_VISIBLE_DEVICES="''${HIP_VISIBLE_DEVICES:-1}"
            export ROCR_VISIBLE_DEVICES="''${ROCR_VISIBLE_DEVICES:-1}"
            export HSA_OVERRIDE_GFX_VERSION="''${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"
            export LLAMA_SERVER_URL="''${LLAMA_SERVER_URL:-http://127.0.0.1:8080}"
            export PATH="$PWD/node_modules/.bin:$PATH"

            echo "llama-server GGUF demo"
            echo "  ./run-server.sh --help"
            echo "  hf --help"
            echo "  python3 client.py --health"
            echo "  ./run-server.sh --pi-smoke-test"
          '';
        };
      }
    );
}
