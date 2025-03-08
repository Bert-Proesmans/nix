{ lib, pkgs, special, config, ... }:
let
  cfg = config.proesmans.vscode;
in
{
  imports = [ special.inputs.vscode-server.nixosModules.default ];

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
