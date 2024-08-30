{ lib, pkgs, flake, config, ... }: {
  imports = [
    # Look at updates to file nixos/modules/module-list.nix
    "${flake.inputs.immich-review}/nixos/modules/services/web-apps/immich.nix"
  ];

  # This overlay should not be applied to the other nixpkgs variant. AKA not using option proesmans.nix.overlays for this.
  nixpkgs.overlays =
    let
      # WARN; In case of overlay misuse prevent the footgun of infinite nixpkgs evaluations. That's why the import
      # is pulled outside the overlay body.
      immich-pkgs = (import flake.inputs.immich-review) {
        inherit (config.nixpkgs) config;
        localSystem = config.nixpkgs.hostPlatform;
      };
    in
    [
      (final: prev: {
        immich-review = immich-pkgs;
        immich = final.immich-review.immich;
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

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
