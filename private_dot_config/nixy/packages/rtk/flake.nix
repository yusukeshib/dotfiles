{
  description = "rtk - Rust Token Killer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Workaround: crates.io currently 403s requests with the
        # default `curl/X Nixpkgs/Y` User-Agent that fetchurl sends.
        # Override fetchurl to send a generic UA so per-crate fetches
        # (used by rustPlatform.cargoLock) succeed. See:
        #   https://github.com/rust-lang/crates.io/issues/13482
        cratesUaOverlay = final: prev: {
          fetchurl = args:
            let
              inject = a: a // {
                curlOptsList = (a.curlOptsList or [])
                  ++ [ "--user-agent" "Nixpkgs-fetchurl" ];
              };
            in
              if builtins.isAttrs args then prev.fetchurl (inject args)
              else prev.fetchurl args;
        };
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ cratesUaOverlay ];
        };
        rtk = pkgs.rustPlatform.buildRustPackage rec {
          pname = "rtk";
          version = "0.39.0";

          src = pkgs.fetchFromGitHub {
            owner = "rtk-ai";
            repo = "rtk";
            rev = "v${version}";
            hash = "sha256-TX4MtR/rq61wxHWYJAO2x3CYvZtkCoXynf45dRC+MVo=";
          };

          cargoLock.lockFile = ./Cargo.lock;

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Rust Token Killer - CLI proxy that minimizes LLM token consumption";
            homepage = "https://github.com/rtk-ai/rtk";
            license = licenses.mit;
            mainProgram = "rtk";
            platforms = platforms.unix;
          };
        };
      in
      {
        packages.default = rtk;
        packages.rtk = rtk;

        devShells.default = pkgs.mkShell {
          buildInputs = [ rtk ];
        };
      }
    );
}
