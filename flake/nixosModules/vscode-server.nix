{ lib, pkgs, flake, config, ... }:
let
  cfg = config.proesmans.vscode;
in
{
  imports = [ flake.inputs.vscode-server.nixosModules.default ];

  options.proesmans.vscode = {
    enable = lib.mkEnableOption "vscode server compatibility";
    nix-dependencies.enable = lib.mkEnableOption "pre-installed dependencies for nix development";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.nix-dependencies.enable) {
      services.vscode-server.enable = true;

      environment.systemPackages = lib.mkIf cfg.nix-dependencies.enable
        (builtins.attrValues { inherit (pkgs) nixpkgs-fmt; });
    })
  ];
}
