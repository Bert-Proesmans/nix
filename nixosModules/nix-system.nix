# { inputs, outputs }:
# let
#   nixpkgs-stable = inputs.nixpkgs-stable;
#   nixpkgs-overlays = builtins.attrValues outputs.overlays;

#   # Add additional package repositories (input flakes) below.
#   # nixpkgs is a symlink to the stable source, kept for consistency with online guides
#   nix-registry = { inherit (inputs) nixpkgs nixpkgs-stable nixpkgs-unstable; };

#   get-inputs-revision = flake-reference: inputs."${flake-reference}".sourceInfo.rev;
#   nix-revs = builtins.listToAttrs (
#     builtins.map (name: { inherit name; value = get-inputs-revision name; }) [ "nixpkgs" "nixpkgs-stable" "nixpkgs-unstable" ]
#   );
# in
{ config, lib, flake-inputs, flake-overlays, ... }:
let
  cfg = config.proesmans.nix;
  nixpkgs = flake-inputs.nixpkgs;
  nixpkgs-stable = flake-inputs.nixpkgs-stable;
  nixpkgs-unstable = flake-inputs.nixpkgs-unstable;
in
{
  options.proesmans.nix = {
    garbage-collect.enable = lib.mkEnableOption "cleanup of nix/store" // { description = "Make the target host automatically cleanup unused reference in the nix store"; };
    garbage-collect.development-schedule.enable = lib.mkEnableOption "lower frequency runs" // { description = "Lower the frequency of gc and adjusted the amount of data to cleanup"; };

    # registry.references = lib.mkOption {
    #   description = "The index archives to store on the host";
    #   type = lib.types.listOf (lib.types.oneOf [ lib.types.str lib.types.path ]);
    #   default = [
    #     nixpkgs
    #     nixpkgs-stable
    #     nixpkgs-unstable
    #   ];
    # };
    registry.fat = lib.mkEnableOption "storing input archives" // { description = "Copy all files from the referenced archives to the host, instead of a link to their online location"; };
  };

  # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/nix.nix
  # Nix configuration
  config = lib.mkMerge [
    ({
      # Fallback quickly if substituters are not available.
      nix.settings.connect-timeout = lib.mkDefault 5;
      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];
      # The default at 10 is rarely enough.
      nix.settings.log-lines = lib.mkDefault 25;
      # Dirty git repo warnings become tiresome really quickly...
      nix.settings.warn-dirty = false;

      # NOTE; The pkgs and lib arguments for every nixos module will be overwritten with a package repository
      # defined from options nixpkgs.*
      nixpkgs.overlays = (builtins.attrValues flake-overlays)
        ++ [
        (_self': _super: {
          # Injecting our own lib only has effect on argument pkgs.lib. This is by design otherwise we end up
          # with an infinite recursion.
          # Overriding lib _must_ be done at the call-site of lib.nixosSystem.
          # REF; https://github.com/NixOS/nixpkgs/issues/156312
          # lib = super.lib // self.outputs.lib;

          # Inject stable packages, initialised with the same configuration as nixpkgs, as pkgs.stable.
          # WARN; This code assumes nixpkgs follows nixpkgs-*un*stable, so the pkgs.stable package set is a way to 
          # (temporarily) stabilise changes.
          # WARN; 'import <flake-input>' will import the '<flake>/default.nix' file. This is _not_ the same 
          # as loading from '<flake>/flake.nix'! flake.nix includes nixos library functions, the old default.nix doesn't.
          #   - '(import nixpkgs).lib' will not have the nixos library function
          #   - 'inputs.nixpkgs.lib' has the nixos library functions
          #
          # Attribute 'pkgs' will contain all unstable package versions.
          # Attribute 'pkgs.stable' contains all stable package versions.
          stable = (import nixpkgs-stable) {
            inherit (config.nixpkgs) config overlays;
            localSystem = config.nixpkgs.hostPlatform;
          };
        })
      ];

      # Trusted users can manage and ad-hoc use substituters, also maintain the nix/store without limits (import and cleanup)
      nix.settings.trusted-users = [ "@wheel" ];

      nix.settings.trusted-substituters = [
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"
        "https://numtide.cachix.org"
        "https://microvm.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
        "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
      ];

      # Avoid copying unnecessary stuff over SSH
      nix.settings.builders-use-substitutes = lib.mkDefault true;

      # Assist nix-direnv, since project devshells aren't rooted in the computer profile, nor stored in /nix/store
      nix.settings.keep-outputs = lib.mkDefault true;
      nix.settings.keep-derivations = lib.mkDefault true;
    })
    (lib.mkIf cfg.garbage-collect.enable {
      nix.gc.automatic = true;
      # Uses the min/max free below, otherwise it's possible to mark and sweep by file age
      # --delete-older-than will also remove gcroots (aka generations, or direnv pins, or home-manager profiles)
      # that are older than the designated duration.
      nix.gc.options = lib.mkDefault "--delete-older-than 14d";

      # When getting close to this amount of free space..
      nix.settings.min-free = lib.mkDefault (512 * 1024 * 1024); # 512MB
      # .. remove this amount of data from the store
      nix.settings.max-free = lib.mkDefault (10 * 1024 * 1024 * 1024); # 10GB
    })
    (lib.mkIf cfg.garbage-collect.development-schedule.enable {
      nix.gc.dates = "monthly";
      # Keep roots for longer, and remove maximum x data each time
      nix.gc.options = "--delete-older-than 90d --max-freed $((2 * 1024**3))"; # 2GB
    })
    ({
      # NOTE; Code similar to <nixpkgs>/nixos/modules/misc/nixpkgs-flake.nix, but adapted for multiple references!
      # REF; https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/nixpkgs-flake.nix

      # Synchronise sources for nix cli v2 and cli v3. V2 uses channels, while we in v3 use flakes.
      nix.nixPath = lib.attrValues (lib.mapAttrs (name: _: "${name}=flake:${name}") config.nix.registry);

      nix.registry = lib.mkMerge [
        # Store sources into the registry as references
        (lib.mkIf (!cfg.registry.fat) (
          builtins.mapAttrs
            (_: value: {
              to = {
                type = "github";
                # WARN; Cannot freely accept inputs because the original reference information has been
                # consumed and we only get a data revision string back.
                # We only know the location of nixpkgs, that's it. If you require more references you'll have
                # to set option nix.registry yourself.
                owner = "NixOS";
                repo = "nixpkgs";
                ref = value.rev;
              };
            })
            {
              inherit nixpkgs nixpkgs-stable nixpkgs-unstable;
            }
        ))

        # Store sources as paths (embedded into the host)
        (lib.mkIf (cfg.registry.fat) (
          builtins.mapAttrs
            (_: value: {
              to = {
                type = "path";
                path = value;
              };
            })
            {
              inherit nixpkgs nixpkgs-stable nixpkgs-unstable;
            }
        ))
      ];
    })
  ];
}
