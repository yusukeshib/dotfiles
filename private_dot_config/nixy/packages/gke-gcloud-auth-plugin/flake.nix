{
  description = "Google Cloud SDK with GKE auth plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        gcloud = pkgs.google-cloud-sdk.withExtraComponents [
          pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
        ];
      in
      {
        packages.default = gcloud;

        devShells.default = pkgs.mkShell {
          buildInputs = [ gcloud ];
        };
      }
    );
}
