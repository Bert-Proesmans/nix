{ lib, flake, config, ... }:
let
  cfg = config.proesmans.home-manager;
in
{
  imports = [ flake.inputs.home-manager.nixosModules.default ];

  options = {
    proesmans.home-manager = {
      enable = lib.mkEnableOption "user profile configuration for interactive users";
    };
  };

  config = (lib.mkIf cfg.enable {
    # Enable more output when switching configuration
    home-manager.verbose = true;
    # Home-manager manages software assigned through option users.users.<name>.packages
    home-manager.useUserPackages = true;
    # Follow the system nix configuration instead of building/using a parallel index
    home-manager.useGlobalPkgs = true;

    # PR; https://github.com/nix-community/home-manager/pull/6622
    # home-manager.users = builtins.intersectAttrs (lib.filterAttrs (_: v: v.isNormalUser) config.users.users) flake.outputs.homeModules.users;
    home-manager.users.bert-proesmans = flake.outputs.homeModules.users.bert-proesmans;
  });
}
