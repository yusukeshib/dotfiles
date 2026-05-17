{
  description = "hunk - Review-first terminal diff viewer for agentic coders";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        version = "0.12.1";

        assets = {
          "aarch64-darwin" = {
            name = "hunkdiff-darwin-arm64";
            hash = "sha256-PuRNsdUXBQ4JYrgCjdsBB7UdHNAeHUvA3i5fTjs6rp0=";
          };
          "x86_64-darwin" = {
            name = "hunkdiff-darwin-x64";
            hash = "sha256-Xvgnn+CptkhsxANriOSrq8wFL/MQidrW8Wm9/l4n94s=";
          };
          "aarch64-linux" = {
            name = "hunkdiff-linux-arm64";
            hash = "sha256-kxXnTITRp0awtWjfks003wVeAMi5tfKYsbtrlGV4HuI=";
          };
          "x86_64-linux" = {
            name = "hunkdiff-linux-x64";
            hash = "sha256-iIs1YyVwas8aEyufSWMN2En6awmKR8yC4n0o8u+GG8Y=";
          };
        };

        asset = assets.${system} or (throw "hunk: unsupported system ${system}");

        hunk = pkgs.stdenvNoCC.mkDerivation {
          pname = "hunk";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://github.com/modem-dev/hunk/releases/download/v${version}/${asset.name}.tar.gz";
            hash = asset.hash;
          };

          sourceRoot = asset.name;

          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 hunk $out/bin/hunk
            ln -s hunk $out/bin/hunkdiff
            if [ -d skills ]; then
              mkdir -p $out/share/hunk
              cp -r skills $out/share/hunk/
            fi
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Review-first terminal diff viewer for agentic coders";
            homepage = "https://github.com/modem-dev/hunk";
            license = licenses.mit;
            mainProgram = "hunk";
            platforms = builtins.attrNames assets;
          };
        };
      in
      {
        packages.default = hunk;
        packages.hunk = hunk;

        devShells.default = pkgs.mkShell {
          buildInputs = [ hunk ];
        };
      }
    );
}
