# This is a function-lambda (Any) -> (Any/nixosModule)
{ inputs }:
let
  vscode-module = inputs.vscode-server.nixosModules.default;
in
# This is a nixOS module; (AttrSet) -> (AttrSet)
{ config, lib, pkgs, ... }:
let
  cfg = config.proesmans.vscode;
in
{
  imports = [ vscode-module ];

  options.proesmans.vscode = {
    enable = lib.mkEnableOption (lib.mdDoc "Enable vscode server compatibility");
    nix-dependencies.enable = lib.mkEnableOption (lib.mdDoc "Pre-install dependencies for nix development");
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.nix-dependencies.enable) {
      services.vscode-server.enable = true;

      environment.systemPackages = lib.mkIf cfg.nix-dependencies.enable
        (builtins.attrValues { inherit (pkgs) nixpkgs-fmt; });
    })
  ];
}
