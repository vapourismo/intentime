{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          intentime = pkgs.swiftPackages.stdenv.mkDerivation {
            pname = "intentime";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [
              pkgs.swift
              pkgs.swiftPackages.swiftpm
            ];

            installPhase = ''
              runHook preInstall
              install -Dm755 "$(swiftpmBinPath)/Intentime" "$out/bin/intentime"
              runHook postInstall
            '';

            meta = {
              description = "Pomodoro timer that lives in the macOS menu bar";
              mainProgram = "intentime";
              platforms = pkgs.lib.platforms.darwin;
            };
          };

          default = self.packages.${system}.intentime;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
        };
      }
    );
}
