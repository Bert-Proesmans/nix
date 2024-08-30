{ flake, config, ... }: {
  imports = [
    # Look at updates to file nixos/modules/module-list.nix
    "${flake.inputs.immich-review}/nixos/modules/services/web-apps/immich.nix"
  ];

  nixpkgs.overlays = [
    (final: prev: {
      immich-review = (import flake.inputs.immich-review) {
        inherit (config.nixpkgs) config overlays;
        localSystem = config.nixpkgs.hostPlatform;
      };
      inherit (final.immich-review) immich;
    })
  ];

  networking.domain = "alpha.proesmans.eu";

  services.openssh.hostKeys = [
    {
      path = "/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";

  services.immich.enable = true;

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
