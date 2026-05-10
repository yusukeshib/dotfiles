{
  description = "rtk - Rust Token Killer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
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
