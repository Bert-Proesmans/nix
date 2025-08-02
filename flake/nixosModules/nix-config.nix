{
  lib,
  flake,
  pkgs,
  config,
  ...
}:
let
  cfg = config.proesmans.nix;
in
{
  options.proesmans.nix = {
    registry.fat-nixpkgs.enable =
      lib.mkEnableOption "adding the sources of flake references to the host"
      // {
        default = true;
        description = ''
          Copy the unpacked source files, resolved from the same input references locked onto this flake, into the target host closure.
          Without this setting only a reference is kept and the source archive is downloaded on first use eg, on invocation of 
          `nix shell <>` or `nix run <>`.
        '';
      };

    overlays = lib.mkOption {
      description = ''
        List of overlay functions that should be added to both {option}`nixpkgs.overlays` and also the stable variant of nixpkgs!
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

    garbage-collect.lower-frequency.enable =
      lib.mkEnableOption "lower frequency executions of nix store garbage collection"
      // {
        description = ''
          Lower the frequency of garbage collection and adjust the amount of data to cleanup each time.
        '';
      };
  };

  config = lib.mkMerge [
    ({
      ## Section about nix command line interactions ##
      # Enable flakes
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      # No building by default!
      # ERROR; You **must** override this setting on builder hosts!
      nix.settings.max-jobs = lib.mkDefault 0;
      # The default at 10 is rarely enough.
      nix.settings.log-lines = lib.mkDefault 25;
      # Dirty git repo warnings become tiresome really quickly...
      nix.settings.warn-dirty = lib.mkDefault false;
    })
    ({
      ## Section about caches and /nix/store manipulations ##

      # Download from cache first
      nix.settings.builders-use-substitutes = lib.mkDefault true;
      nix.settings.connect-timeout = lib.mkDefault 5;

      # This setting allows all users to utilize specific binary caches without specific permissions.
      #
      # NOTE; In general, unless cache objects are output-addressed they *must* also be signed by a trusted public key!
      # SEEALSO; nix.settings.trusted-public-keys
      nix.settings.trusted-substituters = [ ];

      # (Additional) substituters that are only used when user is part of "trusted-user" and explicitly opts-in
      nix.settings.substituters = [
        # 'cache.nixos.org' is always added by default
        # "https://cache.nixos.org"
      ];

      # A store object must be signed by any of these keys otherwise it's not added to /nix/store.
      #
      # WARN; Yes, this means it's possible to block users from downloading objects from online caches on a user/cache-url
      # basis, but does not block importing blocks downloaded manually from those same caches ...
      # There is no other option than allowing these keys, because in that situation only "output-addressed" objects
      # are allowed into /nix/store. Basically only derivations from "fetchers" (the pkgs functions that require a hash
      # of their on-disk contents) are "output-addressed" and that implies we could only _build_ from verified source. At
      # this point there are no _build result_ objects that are "output-addressed".
      #
      # NOTE; Retrieving the public key signature differs per binary cache! There is no single dedicated manner to retrieve
      # this data.
      nix.settings.trusted-public-keys = [
        # 'cache.nixos.org' is always added by default, if the signature ever changes this won't lock us out of downloading
        # prebuilt packages.
        # "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];

      # Trusted users can manage and ad-hoc use substituters, also maintain the nix/store without limits (import and cleanup)
      #
      # ERROR; Executing nixos-rebuild for a remote target performs store manipulations on that target! This is because
      # the system derivation is (normally built locally on build host) not signed with any trusted binary cache key.
      users.groups.nix-wheel = { };
      nix.settings.trusted-users = [
        # NONE !
        # Not even @wheel by default, because adding users to this list is basically giving them root access.
        # And @wheel is list of users that are allowed to use 'sudo', but 'sudo' usage could be restricted. AKA not even sudo
        # users should give full system control (except in naïve environments)!

        "@nix-wheel"
        "@wheel" # TODO; Remove after migration to group nix-wheel completes
      ];
    })
    ({
      ## Section about the nix registry and package channels ##

      # NOTE; Code similar to <nixpkgs>/nixos/modules/misc/nixpkgs-flake.nix, but adapted for multiple flake references!
      # REF; https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/misc/nixpkgs-flake.nix

      # Synchronise sources for nix cli v2 and cli v3. V2 uses channels, while we in v3 use flakes.
      # This setup redirects channel references to their flake counterpart.
      nix.nixPath = lib.attrValues (lib.mapAttrs (name: _: "${name}=flake:${name}") config.nix.registry);

      # Setup universally relevant registries by references.
      nix.registry = lib.mkMerge [
        (lib.mkIf (cfg.registry.fat-nixpkgs.enable == false) {
          # eg; {type = "github", "owner" = "NixOS", repo = "nixpkgs" ... }
          nixpkgs.to = builtins.parseFlakeRef "github:NixOS/nixpkgs" // {
            ref = flake.inputs.nixpkgs.rev;
          };
          nixpkgs-unstable.to = builtins.parseFlakeRef "github:NixOS/nixpkgs" // {
            ref = flake.inputs.nixpkgs-unstable.rev;
          };
          nixpkgs-stable.to = builtins.parseFlakeRef "github:NixOS/nixpkgs" // {
            ref = flake.inputs.nixpkgs-stable.rev;
          };
          # Add more interesting references here!
        })

        (lib.mkIf (cfg.registry.fat-nixpkgs.enable == true) {
          nixpkgs.to = {
            type = "path";
            path = flake.inputs.nixpkgs.outPath;
            narHash = flake.inputs.nixpkgs.narHash;
          };
          nixpkgs-unstable.to = {
            type = "path";
            path = flake.inputs.nixpkgs-unstable.outPath;
            narHash = flake.inputs.nixpkgs-unstable.narHash;
          };
          nixpkgs-stable.to = {
            type = "path";
            path = flake.inputs.nixpkgs-stable.outPath;
            narHash = flake.inputs.nixpkgs-stable.narHash;
          };
          # Add more interesting references here!
        })
      ];
    })
    ({
      ## Section about nixpkgs adjustments ##
      # WARN; There is no mechanism to transform an instantiated nixpkgs with overlays back into a derivation to link into
      # the registry. Overlay changes are not visible and usable from the cli on the target host, at least not without explicitly
      # referring to this flake.

      # Setup default overlays
      #
      # HELP; Add more in the host configuration.
      proesmans.nix.overlays = (builtins.attrValues flake.outputs.overlays);

      # NOTE; The applied overlay effects are visible in the 'pkgs' argument for every nixos module!
      nixpkgs.overlays =
        let
          # ERROR; There lies a footgun within incorectly defining nixpkgs overlays, leading to inifinite evaluation
          # recursion! The import is pulled outside the overlay body to be calculated at most once
          # per modules evaluation (evalModule). See below for more information.
          stable-nixpkgs = (import flake.inputs.nixpkgs-stable) {
            # WARN; passing "overlays" here creates a high likelihood of _eval explosion_ AKA nix uses lots of RAM and
            # cannot close on the result. Basically an undetected infinite recursion!
            #
            # ERROR; DO NOT `inherit (config.nixpkgs) overlays`
            overlays = cfg.overlays;

            config = config.nixpkgs.config;
            localSystem.system = pkgs.system;
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
            # NOTE; Attribute 'pkgs' will contain all unstable package versions.
            # NOTE; Attribute 'pkgs.stable' contains all stable package versions.
            stable = stable-nixpkgs;

            # NOTE; Packages are applied here in current pkgs context. This is better because;
            #   - Dependencies are taken from system package set
            #   - Only one system is evaluated instead of all systems for cross-compilation (if any)
            proesmans = lib.packagesFromDirectoryRecursive {
              inherit (prev) callPackage;
              directory = ../packages;
            };

            # ERROR; Custom packages from this flake were imported under attribute 'proesmans', but references are resolved from
            # the package scope root where the referenced packages do not exist.
            # Referenced packages are made available in the scope root to resolve those errors.
            inherit (final.proesmans) unsock backblaze-installer backblaze-install-patched;
          })
        ];
    })
    ({
      ## Section about nix store garbage collection ##

      # Optimisation is making hardlinks between nix store objects when file contents are identical.
      nix.settings.auto-optimise-store = false;

      # Automated cleanup is removing nix store objects when the file system runs low on free space.
      # This behaviour is automatically executed in the background during nix evaluations/builds when
      # min-free value is larger than zero (0).
      #
      # WARN; This functionaly is different from nix-collect-garbage. Both have their own disjunct
      # configuration parameters!
      #
      # When getting close to this amount of free space on the /nix/store filesystem..
      nix.settings.min-free = lib.mkDefault 0; # DISABLED
      # .. (attempt to) remove this amount of data from the store.
      nix.settings.max-free = lib.mkDefault (10 * 1024 * 1024 * 1024); # 10GB

      # Enables scheduled cleanup of store objects
      nix.gc.automatic = lib.mkDefault true;
      # All built derivations can be topologically sorted with their root being a called 'gcroot'.
      # Derivations that are linked to a gcroot will not be cleaned up!
      #
      # These gcroots eg, nixos generations, direnv pins or home-manager generations (aka profiles),
      # can be removed based on age.
      #
      # SEEALSO; Run `nix-store --gc --print-roots` to view the gcroots nix currently knows about.
      nix.gc.options = lib.mkDefault "--delete-older-than 30d --max-freed ${
        toString (20 * 1024 * 1024 * 1024)
      }"; # 20GB
    })
    (lib.mkIf cfg.garbage-collect.lower-frequency.enable {
      # Keep roots for longer, and remove maximum x data each time
      nix.settings.max-free = 2 * 1024 * 1024 * 1024; # 2GB
      nix.gc.dates = "weekly";
      nix.gc.options = "--delete-older-than 90d --max-freed ${toString (20 * 1024 * 1024 * 1024)}"; # 20GB
    })
  ];

}
