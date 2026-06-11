{
  description = "OpenCode + Ollama self-hosting demo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            rocmSupport = system == "x86_64-linux";
          };
        };

        ollamaPackage = if system == "x86_64-linux" then pkgs.ollama-rocm else pkgs.ollama;

        demo = pkgs.writeShellApplication {
          name = "opencode-ollama-demo";
          runtimeInputs = with pkgs; [ bash ];
          text = ''
            exec bash ${./demo.sh} "$@"
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            git
            jq
            ollamaPackage
            opencode
          ];

          shellHook = ''
            export OLLAMA_HOST="''${OLLAMA_HOST:-127.0.0.1:11434}"
            export OPENCODE_CONFIG="''${OPENCODE_CONFIG:-$PWD/opencode.json}"
            export HSA_OVERRIDE_GFX_VERSION="''${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"

            echo "OpenCode + Ollama demo"
            echo "  1. ./demo.sh --run"
            echo "  2. ./demo.sh --opencode"
          '';
        };

        packages.default = demo;

        apps.default = {
          type = "app";
          program = "${demo}/bin/opencode-ollama-demo";
        };

        apps.demo = self.apps.${system}.default;
      }
    );
}
