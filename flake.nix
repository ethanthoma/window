{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/devshell";
    };
    zig2nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Cloudef/zig2nix";
    };
  };

  outputs =
    inputs@{ ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.devshell.flakeModule ];

      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, ... }:
        let
          env = inputs.zig2nix.outputs.zig-env.${system} { };

          depsWayland = [
            pkgs.wayland
            pkgs.wayland-scanner
            pkgs.wayland-protocols
            pkgs.libxkbcommon
          ];

          depsX11 = [
            pkgs.libx11
            pkgs.xorgproto
          ];

          depsLinux = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (depsWayland ++ depsX11);

          pkgConfigPath = pkgs.lib.concatStringsSep ":" (
            map (dep: "${dep.dev or dep}/lib/pkgconfig") depsLinux
            ++ map (dep: "${dep}/share/pkgconfig") depsLinux
          );
        in
        {
          devshells.default = {
            packages = [
              env.pkgs.zls
              pkgs.pkg-config
            ]
            ++ depsLinux;

            env = [
              {
                name = "PKG_CONFIG_PATH";
                value = pkgConfigPath;
              }
            ];

            commands = [
              { package = env.pkgs.zig; }
              { package = pkgs.tokei; }
            ];
          };
        };
    };
}
