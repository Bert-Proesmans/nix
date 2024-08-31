{ lib, pkgs, flake, config, ... }:
let
  # Create a new sub-folder within the shared mount to isolate data from different major versions of postgres
  state-postgres-dir = "/data/state-postgresql/${config.services.postgresql.package.psqlSchema}";
  wal-postgres-dir = "/data/wal-postgresql/${config.services.postgresql.package.psqlSchema}";
in
{
  imports = [
    # Look at updates to file nixos/modules/module-list.nix
    "${flake.inputs.immich-review}/nixos/modules/services/web-apps/immich.nix"
  ];

  networking.domain = "alpha.proesmans.eu";

  services.openssh.hostKeys = [
    {
      path = "/data/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/data/seeds/ssh_host_ed25519_key";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

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
      (final: _prev: {
        immich-review = immich-pkgs;
        immich = final.immich-review.immich;
      })
    ];

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;

    # TEMPORARY
    redis.host = "/run/redis-immich/redis.sock";
  };

  # TEMPORARY
  systemd.services.immich-server.after = [ "redis-immich.service" "postgresql.service" ];
  systemd.services.immich-machine-learning.after = [ "redis-immich.service" "postgresql.service" ];

  systemd.tmpfiles.settings."10-postgres-ownership" = {
    # ERROR; Parent directories are still owned by root so something must create the required directories
    # for the service users. This approach is an alternative to the unit config attribute StateDirectory.
    #
    # NOTE; Unix user for the postgres service is fixed to "postgres"
    "${state-postgres-dir}".d = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
    "${state-postgres-dir}/*".Z = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
    "${wal-postgres-dir}".d = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
    "${wal-postgres-dir}/*".Z = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
  };

  services.postgresql = {
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_15_jit;
    dataDir = state-postgres-dir;
    initdbArgs = [
      # WAL is written to another filesystem to limit denial-of-service (DOS) when clients open
      # transactions for a long time.
      "--waldir=${wal-postgres-dir}"
      # Encode in UTF-8
      "--encoding=UTF8"
      # Sort in C, aka use straightforward byte-ordering
      "--no-locale" # PERFORMANCE
    ];
    # ZFS Optimization
    settings.full_page_writes = "off";
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
