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

              app="$out/Applications/Intentime.app"
              mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out/bin"

              install -Dm755 "$(swiftpmBinPath)/Intentime" "$app/Contents/MacOS/Intentime"
              install -Dm644 Info.plist "$app/Contents/Info.plist"

              if [ -d Resources ]; then
                cp -R Resources/. "$app/Contents/Resources/"
              fi

              printf 'APPL????' > "$app/Contents/PkgInfo"
              ln -s "$app/Contents/MacOS/Intentime" "$out/bin/intentime"

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

        apps = {
          intentime = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "launch-intentime" ''
                open -a "${self.packages.${system}.intentime}/Applications/Intentime.app"
              ''
            );
          };

          default = self.apps.${system}.intentime;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
        };
      }
    );
}
