{
  description = "Wayland + WebGPU windowing library";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    zig2nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Cloudef/zig2nix";
    };
  };

  outputs =
    inputs@{ self, ... }:

    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.devshell.flakeModule ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ inputs.devshell.overlays.default ];
          };

          env = inputs.zig2nix.outputs.zig-env.${system} { };
        in
        {
          _module.args.pkgs = pkgs;

          devshells.default = {
            packages = [
              env.pkgs.zls
              pkgs.wayland
              pkgs.wayland-protocols
              pkgs.wayland-scanner
              pkgs.libxkbcommon
              pkgs.pkg-config
            ];

            commands = [
              { package = env.pkgs.zig; }
              {
                name = "claude";
                package = pkgs.claude-code;
              }
            ];

            env = [
              {
                name = "WAYLAND_PROTOCOLS_DIR";
                eval = "${pkgs.wayland-protocols}/share/wayland-protocols";
              }
              {
                name = "WAYLAND_SCANNER";
                eval = "$(which wayland-scanner)";
              }
              {
                name = "PKG_CONFIG_PATH";
                eval = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
                  pkgs.wayland
                  pkgs.libxkbcommon
                ];
              }
              {
                name = "LD_LIBRARY_PATH";
                eval = pkgs.lib.makeLibraryPath [
                  pkgs.wayland
                  pkgs.libxkbcommon
                ];
              }
            ];
          };
        };
    };
}
