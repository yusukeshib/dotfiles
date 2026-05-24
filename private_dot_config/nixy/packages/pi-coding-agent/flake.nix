{
  description = "pi-coding-agent — wraps the published npm tarball so we can always get the latest release";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        info = builtins.fromJSON (builtins.readFile ./version.json);

        pi-coding-agent = pkgs.buildNpmPackage {
          pname = "pi-coding-agent";
          version = info.version;

          # Use the published npm tarball directly. It ships pre-built `dist/`
          # plus an `npm-shrinkwrap.json`, so buildNpmPackage can resolve deps
          # deterministically without us touching the source repo.
          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${info.version}.tgz";
            hash = info.srcHash;
          };

          npmDepsHash = info.npmDepsHash;

          # dist/ is already built; we just need node_modules.
          dontNpmBuild = true;

          # Native deps inside transitive packages (e.g. koffi) ship prebuilt
          # binaries — don't try to rebuild them.
          npmFlags = [ "--ignore-scripts" ];

          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];

          # Put ripgrep + fd on PATH like nixpkgs does.
          postInstall = ''
            wrapProgram $out/bin/pi \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ripgrep pkgs.fd ]}
          '';

          meta = with pkgs.lib; {
            description = "Coding agent CLI with read, bash, edit, write tools and session management";
            homepage = "https://pi.dev/";
            downloadPage = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent";
            license = licenses.mit;
            mainProgram = "pi";
            platforms = platforms.unix;
          };
        };
      in
      {
        packages.default = pi-coding-agent;
        packages.pi-coding-agent = pi-coding-agent;
      });
}
