{
  description = "Build environment for the openFPGA SNES core (Analogue Pocket, Cyclone V)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Quartus is unfree; allow just it so users don't need global allowUnfree
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "quartus-prime-lite"
            "quartus-prime-lite-unwrapped"
          ];
      };

      # Only fetch Cyclone V device support
      quartus = pkgs.quartus-prime-lite.override {
        supportedDevices = [ "Cyclone V" ];
      };

      build-core = pkgs.writeShellApplication {
        name = "build-core";
        runtimeInputs = [
          quartus
          pkgs.python3
        ];
        text = builtins.readFile ./build.sh;
      };
    in
    {
      packages.${system} = {
        inherit quartus build-core;
        default = build-core;
      };

      apps.${system}.default = {
        type = "app";
        program = "${build-core}/bin/build-core";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          quartus
          pkgs.python3
          build-core
        ];
      };
    };
}
