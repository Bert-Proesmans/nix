{ inputs }:
let
  nixpkgs-unstable = inputs.nixos-unstable;
  # Add additional package repositories (input flakes) below.
  # nixpkgs is a symlink to the stable source, kept for consistency with online guides
  nix-registry = { inherit (inputs) nixpkgs nixos-stable nixos-unstable; };
in
{ config, lib, ... }:
let
  cfg = config.proesmans.nix;
in
{
  options.proesmans.nix = {
    linux-64 = lib.mkEnableOption (lib.mdDoc "Configure the target system as 64-bit linux");
    garbage-collect.enable = lib.mkEnableOption (lib.mdDoc "Make the target host automatically cleanup unused reference in the nix store");
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

      # NOTE; The pkgs and lib arguments for every nixos module will be overwritten with a package repository
      # defined from options nixpkgs.*
      nixpkgs.overlays = [
        (_self': super: {
          # Injecting our own lib only has effect on argument pkgs.lib. This is by design otherwise we end up
          # with an infinite recursion.
          # Overriding lib _must_ be done at the call-site of lib.nixosSystem.
          # REF; https://github.com/NixOS/nixpkgs/issues/156312
          # lib = super.lib // self.outputs.lib;

          # Inject unstable packages, initialised with the same configuration as nixpkgs, as pkgs.unstable
          # WARN; This will import the default.nix configuration, which lacks information from the flake.nix
          # file;
          #   - 'lib' will not have the nixos library function
          #   - 'pkgs' will have all package definitions
          unstable = (import nixpkgs-unstable) {
            inherit (config.nixpkgs) config overlay;
            localSystem = config.nixpkgs.hostPlatform;
          };
        })
      ];

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
    (lib.mkIf cfg.linux-64 {
      # Define the platform type of the target configuration
      nixpkgs.hostPlatform = lib.systems.examples.gnu64;

      # Make legacy nix commands consistent with flake sources!
      # Register versioned flake inputs into the nix registry for flake subcommands
      # Register versioned flake inputs as channels for nix (v2) commands

      # Each input is mapped to 'nix.registry.<name>.flake = <flake store-content>'
      nix.registry = lib.mapAttrs (_name: flake: { inherit flake; }) nix-registry;

      nix.nixPath = [ "/etc/nix/path" ];
      environment.etc = lib.mapAttrs' (name: value: { name = "nix/path/${name}"; value.source = value.flake; }) config.nix.registry;
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
