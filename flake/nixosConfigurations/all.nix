{ flake, lib }:
let
  # Deprecated, use nixpkgs.hostPlatform option instead (inside configuration)
  system = null;

  # NixOS modules that implement partial host configuration
  # eg; dns server program configuration, reused by all the dns server hosts (OSI layer 7 high-availability)
  # eg; virtual machine guest configuration, reused by all hosts that are running on top of a hypervisor
  profiles = lib.filterAttrs (n: _: n != "archive") flake.outputs.nixosModules.profiles;
  modules = builtins.attrValues (lib.filterAttrs (n: _: n != "profiles" && n != "archive") flake.outputs.nixosModules);

  specialArgs = {
    # Define arguments here that must be be resolvable at module import stage.
    #
    # For everything else use the _module.args option instead (inside configuration).
    # SEEALSO; meta-module, below
    flake = {
      inherit profiles;
      inherit (flake) inputs;
      outputs = {
        # NOTE; Packages are not made available because they need to be re-evaluated within the package scope of the target host
        # anyway. Their evaluation could change depending on introduced overlays!
        inherit (flake.outputs) overlays;
      };
    };
  };
in
{
  development = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      ({
        # This is an anonymous module and requires a marker for error messages and import deduplication.
        _file = "${./all.nix}#development";

        config = {
          # DO NOT USE `flake` TO IMPORT STUFF !
          # _module.args.flake = flake;

          # Nixos utils package is available as module argument, made available sorta like below.
          #_module.args.utils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" { inherit lib config pkgs; };

          # The hostname of each configuration _must_ match their attribute name.
          # This prevent the footgun of desynchronized identifiers.
          networking.hostName = lib.mkForce "development";
        };
      })
      ./development/configuration.nix
    ];
  };
}
