{ flake, lib }:
let
  # Deprecated, use nixpkgs.hostPlatform option instead (inside configuration)
  system = null;

  # NixOS modules that implement partial host configuration
  profiles = flake.outputs.nixosModules.profiles;
  modules = builtins.attrValues (lib.filterAttrs (n: _: n != "profiles") flake.outputs.nixosModules);

  specialArgs = {
    # Define arguments here that must be be resolvable at module import stage.
    #
    # For everything else use the _module.args option instead (inside configuration).
    # SEEALSO; meta-module, below
    special = {
      inherit profiles;
      inherit (flake) inputs;
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
          _module.args.flake = flake;
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
