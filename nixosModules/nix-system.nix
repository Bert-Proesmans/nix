{ inputs }:
let
  # Add additional package repositories (input flakes) below.
  # nixpkgs is a symlink to the stable source, kept for consistency with online guides
  nix-registry = { inherit (inputs) nixpkgs nixos-stable nixos-unstable; };
in
{ config, lib, ... }: {
  # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/nix.nix
  # Nix configuration

  # Fallback quickly if substituters are not available.
  nix.settings.connect-timeout = 5;

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];

  # The default at 10 is rarely enough.
  nix.settings.log-lines = lib.mkDefault 25;

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
  nix.settings.builders-use-substitutes = true;

  # Assist nix-direnv, since project devshells aren't rooted in the computer profile, nor stored in /nix/store
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;

  # Make legacy nix commands consistent with flake sources!
  # Register versioned flake inputs into the nix registry for flake subcommands
  # Register versioned flake inputs as channels for nix (v2) commands

  # Each input is mapped to 'nix.registry.<name>.flake = <flake store-content>'
  nix.registry = lib.mapAttrs (_name: flake: { inherit flake; }) nix-registry;

  nix.nixPath = [ "/etc/nix/path" ];
  environment.etc = lib.mapAttrs'
    (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    })
    config.nix.registry;
}
