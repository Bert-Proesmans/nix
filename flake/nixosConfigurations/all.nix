{ flake, lib }:
let
  inherit (flake.outputs) facts;

  # "System" is deprecated, set nixpkgs.hostPlatform option inside configuration instead
  system = null;

  # NixOS modules that implement partial host configuration
  # eg; dns server program configuration, reused by all the dns server hosts (OSI layer 7 high-availability)
  # eg; virtual machine guest configuration, reused by all hosts that are running on top of a hypervisor
  profiles = lib.filterAttrs (n: _: n != "archive") flake.outputs.nixosModules.profiles;
  modules = builtins.attrValues (
    lib.filterAttrs (n: _: n != "profiles" && n != "archive") flake.outputs.nixosModules
  );

  specialArgs = {
    # Define arguments here that must be be resolvable at module import stage.
    #
    # For everything else use the _module.args option instead (inside configuration).
    flake = {
      inherit profiles;
      inherit (flake) inputs;
      outputs = {
        # NOTE; Packages are not made available because they need to be re-evaluated within the package scope of the target host
        # anyway. Their evaluation could change depending on introduced overlays!
        inherit (flake.outputs) overlays homeModules;
      };
      # Path where media assets are stored for documentation purposes
      # NOTE; $flake points to the flake directory inside the repository! The repository is in its entirety copied into /nix/store
      # but the flake string representation points towards the flake.nix parent folder, aka repo sub folder "flake".
      documentationAssets = "${builtins.dirOf flake}/documentation/assets";
    };
  };
in
{
  development = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      (
        { lib, config, ... }:
        {
          # This is an anonymous module and requires a marker for error messages and import deduplication.
          _file = __curPos.file;

          config = {
            # DO NOT USE `flake` TO IMPORT STUFF !
            # _module.args.flake = flake;

            # Nixos utils package is available as module argument, made available sorta like below.
            #_module.args.utils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" { inherit lib config pkgs; };

            # The hostname of each configuration _must_ match their attribute name.
            # This prevent the footgun of desynchronized identifiers.
            networking.hostName = lib.mkForce "development";

            # Communicate facts about this and other hosts.
            proesmans.facts = facts // {
              self = lib.mkForce config.proesmans.facts."development";
            };
          };
        }
      )
      ./development/configuration.nix
    ];
  };

  buddy = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      (
        { lib, config, ... }:
        {
          _file = __curPos.file;

          config = {
            networking.hostName = lib.mkForce "buddy";
            proesmans.facts = facts // {
              self = lib.mkForce config.proesmans.facts."buddy";
            };
          };
        }
      )
      ./buddy/configuration.nix
    ];
  };

  "01-fart" = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      (
        { lib, config, ... }:
        {
          _file = __curPos.file;

          config = {
            networking.hostName = lib.mkForce "01-fart";
            proesmans.facts = facts // {
              self = lib.mkForce config.proesmans.facts."01-fart";
            };
          };
        }
      )
      ./01-fart/configuration.nix
    ];
  };

  "02-fart" = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      (
        { lib, config, ... }:
        {
          _file = __curPos.file;

          config = {
            networking.hostName = lib.mkForce "02-fart";
            proesmans.facts = facts // {
              self = lib.mkForce config.proesmans.facts."02-fart";
            };
          };
        }
      )
      ./02-fart/configuration.nix
    ];
  };

  freddy = lib.nixosSystem {
    inherit lib system specialArgs;
    modules = modules ++ [
      flake.inputs.nix-topology.nixosModules.default
      (
        { lib, config, ... }:
        {
          _file = __curPos.file;

          config = {
            networking.hostName = lib.mkForce "freddy";
            proesmans.facts = facts // {
              self = lib.mkForce config.proesmans.facts."freddy";
            };
          };
        }
      )
      ./freddy/configuration.nix
    ];
  };
}
