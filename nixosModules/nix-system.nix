{ config, lib, flake, flake-overlays, ... }:
let
  cfg = config.proesmans.nix;

  # Information on where to find the flake sources files
  flake-references = flake.meta.inputs;
  # Information on the flake source files in the /nix/store
  flake-sources = flake.inputs;
in
{
  options.proesmans.nix = {
    garbage-collect.enable = lib.mkEnableOption "cleanup of nix/store" // {
      description = ''
        Make the target host automatically cleanup unused reference in the nix store
      '';
    };
    garbage-collect.development-schedule.enable = lib.mkEnableOption "lower frequency runs" // {
      description = ''
        Lower the frequency of gc and adjusted the amount of data to cleanup
      '';
    };
    registry.nixpkgs.fat = lib.mkEnableOption "adding inputs to closure" // {
      description = ''
        Copy all files from the nixpkgs inputs (stable + unstable) to the host, instead of a link to their online location.
        Adding the files will increase the closure size more than storing only a reference.
      '';
    };
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
          stable = (import flake-sources.nixpkgs-stable) {
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

      # Setup universally relevant registries by references.
      nix.registry = lib.mkMerge [
        (lib.mkIf (cfg.registry.nixpkgs.fat == false) {
          # WARN; Assumes nixpkgs follows input nixpkgs-unstable. This is hardcoded instead of the robust implementation
          # of resolving all follow links to find the proper url!
          #
          # WARN; Assumes all inputs are defined with 'url' attribute instead of the full syntax
          # eg; {type = "github", "owner" = "NixOS", repo = "nixpkgs" ... }
          nixpkgs.to = builtins.parseFlakeRef flake-references.nixpkgs-unstable.url
            // { ref = flake-sources.nixpkgs-unstable.rev; };
          nixpkgs-unstable.to = builtins.parseFlakeRef flake-references.nixpkgs-unstable.url
            // { ref = flake-sources.nixpkgs-unstable.rev; };
          nixpkgs-stable.to = builtins.parseFlakeRef flake-references.nixpkgs-stable.url
            // { ref = flake-sources.nixpkgs-stable.rev; };
        })

        (lib.mkIf (cfg.registry.nixpkgs.fat == true) {
          nixpkgs.to = {
            type = "path";
            path = flake-sources.nixpkgs.outPath;
            narHash = flake-sources.nixpkgs.narHash;
          };
          nixpkgs-unstable.to = {
            type = "path";
            path = flake-sources.nixpkgs-unstable.outPath;
            narHash = flake-sources.nixpkgs-unstable.narHash;
          };
          nixpkgs-stable.to = {
            type = "path";
            path = flake-sources.nixpkgs-stable.outPath;
            narHash = flake-sources.nixpkgs-stable.narHash;
          };
        })
      ];
    })
  ];
}
