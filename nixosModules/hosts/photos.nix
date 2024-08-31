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

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # ZFS optimization
  services.postgresql = {
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_15_jit;
    # Hardcoded to do bind mount mangling!
    dataDir = "/var/lib/postgres/${config.services.postgresql.package.psqlSchema}";
    settings.full_page_writes = "off";
  };

  systemd.mounts = [
    {
      what = "/data/db/state";
      where = "/var/lib/postgres/${config.services.postgresql.package.psqlSchema}";
      type = "none";
      options = "bind";
      requiredBy = [ config.systemd.services.postgresql.name ];
    }
    {
      what = "/data/db/wal";
      where = "/var/lib/postgres/${config.services.postgresql.package.psqlSchema}/pg_wal";
      type = "none";
      options = "bind";
      requiredBy = [ config.systemd.services.postgresql.name ];
    }
  ];

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
