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
    overlays = lib.mkOption {
      description = ''
        List of overlay functions that should be added to both {option}`nixpkgs.overlays`, but also the stable variant of nixpkgs!
        This option exists to prevent an infinite recursion through overlay re-use.

        WARNING; Use this option instead of nixpkgs.overlays, as the overlays passed directly to nixpkgs.overlays will not be applied
        to the stable package set!
      '';
      type = lib.types.listOf (lib.types.functionTo (lib.types.functionTo lib.types.attrs));
      default = [ ];
      example = lib.literalExpression ''
        [
          (final: prev: {
            new-attribute = <pkgs-derivation>;
            new-name-for-attribute = final.new-attribute;
          })
        ]
      '';
    };

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
      # No building by default!
      # ERROR; You must override this setting on builder hosts!
      nix.settings.max-jobs = lib.mkDefault 0;
      # The default at 10 is rarely enough.
      nix.settings.log-lines = lib.mkDefault 25;
      # Dirty git repo warnings become tiresome really quickly...
      nix.settings.warn-dirty = false;

      # Setup default overlays, you can add more in your own configuration.
      proesmans.nix.overlays = (builtins.attrValues flake-overlays);

      # NOTE; The pkgs and lib arguments for every nixos module will be overwritten with a package repository
      # defined from options nixpkgs.*
      nixpkgs.overlays =
        let
          # WARN; In case of overlay misuse prevent the footgun of infinite nixpkgs evaluations. That's why the import
          # is pulled outside the overlay body.
          stable-nixpkgs = (import flake-sources.nixpkgs-stable) {
            # WARN; passing "overlays" here creates a high likelihood of _eval explosion_ AKA nix uses lots of RAM and
            # cannot close on the result. Basically an undetected infinite recursion!
            # WARN - inherit (config.nixpkgs) overlays
            overlays = cfg.overlays; # Breaks overlay recursion cycle

            config = config.nixpkgs.config;
            localSystem = config.nixpkgs.hostPlatform;
          };
        in
        cfg.overlays
        ++ [
          (final: prev: {
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
            stable = stable-nixpkgs;
            #
            # NOTE; Packages are applied here in current pkgs context. This is better because;
            #   - Dependencies are taken from system package set
            #   - Only one system is evaluated instead of all systems for cross-compilation (if any)
            proesmans = builtins.mapAttrs (_: recipe: prev.callPackage recipe { }) (lib.rakeLeaves ../packages);
            # ERROR; special function unsock.wrap throws error about unresolved import "unsock"
            # Need to special case unsock and pull it into the toplevel scope of pkgs.
            unsock = final.proesmans.unsock;
          })
        ];

      # Trusted users can manage and ad-hoc use substituters, also maintain the nix/store without limits (import and cleanup)
      nix.settings.trusted-users = [
        # NONE !
        # Not even @wheel by default, because adding users to this list is basically giving them root access.
        # And @wheel is list of users that are allowed to use 'sudo', but 'sudo' usage could be restricted. AKA not even sudo
        # should give full system control (except in naïve environments)!

        # TODO; Currently required for remote nixos-rebuild
        "@wheel"
      ];

      # Avoid copying unnecessary stuff over SSH
      nix.settings.builders-use-substitutes = lib.mkDefault true;

      # This setting allows all users to utilize specific binary caches without specific permissions.
      #
      # NOTE; Unless objects are output-addressed, the objects also must be signed by a trusted public key!
      # SEEALSO; nix.settings.trusted-public-keys
      nix.settings.trusted-substituters = [
        # The hydra build cache is listed as "substituter", but only these situations make use of those entries;
        # - <substituter> is in list "trusted-substituters"
        # - <user> is in the list "trusted-users"
        #
        # By appending the hydra build cache to this list it will always be used
        "https://cache.nixos.org"
      ];

      # Substituters that are only used if user is part of "trusted-user", or substituter is part of "trusted-substituter"
      nix.settings.substituters = [
        # WARN; Added here because this flake can utilize them and `nixos-rebuild --use-substituters`
        # requires preconfiguration on the destination host!
        "https://nix-community.cachix.org"
        "https://microvm.cachix.org"
      ];

      # A store object must be signed by any of these keys otherwise it's not added to /nix/store.
      #
      # WARN; Yes, this means it's possible to block users from downloading objects from online caches on a user/cache-url
      # basis, but does not block importing blocks downloaded manually from those same caches ... 
      # There is no other option than allowing these keys, because in that situation only "output-addressed" objects
      # are allowed into /nix/store. Basically only derivations from "fetchers" (the pkgs functions that require a hash
      # of their on-disk contents) are "output-addressed" and that implies we could only _build_ from verified source. At
      # this point there are no _build result_ objects that are "output-addressed".
      nix.settings.trusted-public-keys = [
        # WARN; Added here because this flake can utilize them and `nixos-rebuild --use-substituters`
        # requires preconfiguration on the destination host!
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
      ];

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
