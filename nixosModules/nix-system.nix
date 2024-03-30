{ inputs }:
let
  nixpkgs-stable = inputs.nixpkgs-stable;
  # Add additional package repositories (input flakes) below.
  # nixpkgs is a symlink to the stable source, kept for consistency with online guides
  nix-registry = { inherit (inputs) nixpkgs nixpkgs-stable nixpkgs-unstable; };

  get-inputs-revision = flake-reference: inputs."${flake-reference}".sourceInfo.rev;
  nix-revs = builtins.listToAttrs (
    builtins.map (name: { inherit name; value = get-inputs-revision name; }) [ "nixpkgs" "nixpkgs-stable" "nixpkgs-unstable" ]
  );
in
{ config, lib, ... }:
let
  cfg = config.proesmans.nix;
in
{
  options.proesmans.nix = {
    linux-64 = lib.mkEnableOption (lib.mdDoc "Configure the target system as 64-bit linux");
    garbage-collect.enable = lib.mkEnableOption (lib.mdDoc "Make the target host automatically cleanup unused reference in the nix store");
    references-on-disk = lib.mkEnableOption (lib.mdDoc "Copy all files for all stored flake references onto the filesystem") // { default = true; };
  };

  # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/nix.nix
  # Nix configuration
  config = lib.mkMerge [
    ({
      # Force nix flake check to evaluate and build derivation of this module->config->nixosSystem
      _module.check = true;
      # Fallback quickly if substituters are not available.
      nix.settings.connect-timeout = lib.mkDefault 5;
      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];
      # The default at 10 is rarely enough.
      nix.settings.log-lines = lib.mkDefault 25;
      # Dirty git repo becomes tiresome really quickly...
      nix.settings.warn-dirty = false;

      # NOTE; The pkgs and lib arguments for every nixos module will be overwritten with a package repository
      # defined from options nixpkgs.*
      nixpkgs.overlays = [
        (_self': _super: {
          # Injecting our own lib only has effect on argument pkgs.lib. This is by design otherwise we end up
          # with an infinite recursion.
          # Overriding lib _must_ be done at the call-site of lib.nixosSystem.
          # REF; https://github.com/NixOS/nixpkgs/issues/156312
          # lib = super.lib // self.outputs.lib;

          # Inject stable packages, initialised with the same configuration as nixpkgs, as pkgs.stable.
          # The default nixpkgs follows nixpkgs-unstable, so the pkgs.stable is a way to (temporarily) stabilise changes.
          # WARN; 'import <flake-input>' will import the '<flake>/default.nix' file. This is _not_ the same 
          # as loading from '<flake>/flake.nix'! flake.nix includes nixos library functions, the old default.nix doesn't.
          #   - '(import nixpkgs).lib' will not have the nixos library function
          #   - 'inputs.nixpkgs.lib' has the nixos library functions
          #
          # 'pkgs' will contain all unstable package versions.
          # 'pkgs.stable' contains all stable package versions.
          stable = (import nixpkgs-stable) {
            inherit (config.nixpkgs) config overlay;
            localSystem = config.nixpkgs.hostPlatform;
          };
        })
      ];

      # Need to explicitly set trusted users so they can push additional content to the machine
      # TODO; Figure out what trusted-users exactly means; proper usage might involve a two-step process
      # by privileged publishing to a build cache, and pulling from trusted build caches. Probably need a dedicated
      # build host too.
      # REF; https://nixos.wiki/wiki/Nixos-rebuild
      nix.settings.trusted-users = [ "@wheel" ];

      # Enroll some more trusted binary caches
      nix.settings.trusted-substituters = [
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"
        "https://numtide.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      ];

    })
    (lib.mkIf (!cfg.references-on-disk) {
      # Make legacy nix commands consistent with flake sources!
      # Register versioned flake inputs into the nix registry for flake subcommands
      # Register versioned flake inputs as channels for nix (v2) commands

      # Map channels to the pinned references inside the flake registry
      # eg; "nixpkgs=flake:nixpkgs"
      #
      # See also `nix.registry.<name>` for the registry definitions
      nix.nixPath = lib.mapAttrsToList (name: _: "${name}=flake:${name}") nix-revs;

      # Create a binding from a flake reference to a flake repository, at the correct revision.
      # eg; nix.registry.nixpkgs.to.{..repo = "nixpkgs"} => references github:nixos/nixpkgs
      #
      # See also `nix.registry.<name>.flake` for loading the flake 
      nix.registry = builtins.mapAttrs
        (_: rev: {
          to = {
            type = "github";
            owner = "NixOS";
            repo = "nixpkgs";
            ref = rev;
          };
        })
        nix-revs;
    })
    (lib.mkIf cfg.references-on-disk {
      # Append searchpath for channel package indexes
      nix.nixPath = [ "/etc/nix/path" ];
      # Link package index files (aka flake source) into the right filesystem location for channel data lookup
      environment.etc = lib.mapAttrs' (name: value: { name = "nix/path/${name}"; value.source = value.flake; }) config.nix.registry;

      # The option nix.registry.<name>.flake is a shortcut for storing metadata about a flake reference.
      # eg; 'nix.registry.nixpkgs.flake => nixpkgs = /nix/store/<output hash at git revision>/<files>'
      #
      # NOTE; The trick here is that the nix store paths will match exactly on the build and target host;
      #   - build host; nix store files are loaded by nix flake commands
      #   - target host; nix store files are installed because they are part of the entire system closure,
      #     see `environment.etc."/nix/path/nixpkgs"`.
      nix.registry = lib.mapAttrs (_: flake: { inherit flake; }) nix-registry;
    })
    (lib.mkIf cfg.linux-64 {
      # Define the platform type of the target configuration
      nixpkgs.hostPlatform = lib.systems.examples.gnu64;
    })
    (lib.mkIf cfg.garbage-collect.enable {
      # Avoid disk full issues
      nix.settings.max-free = lib.mkDefault (3000 * 1024 * 1024);
      nix.settings.min-free = lib.mkDefault (512 * 1024 * 1024);

      # TODO: cargo culted.
      nix.daemonCPUSchedPolicy = lib.mkDefault "batch";
      nix.daemonIOSchedClass = lib.mkDefault "idle";
      nix.daemonIOSchedPriority = lib.mkDefault 7;

      # Make builds to be more likely killed than important services.
      # 100 is the default for user slices and 500 is systemd-coredumpd@
      # We rather want a build to be killed than our precious user sessions as builds can be easily restarted.
      systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = lib.mkDefault 250;

      # Avoid copying unnecessary stuff over SSH
      nix.settings.builders-use-substitutes = lib.mkDefault true;

      # Assist nix-direnv, since project devshells aren't rooted in the computer profile, nor stored in /nix/store
      nix.settings.keep-outputs = lib.mkDefault true;
      nix.settings.keep-derivations = lib.mkDefault true;
    })
  ];
}
