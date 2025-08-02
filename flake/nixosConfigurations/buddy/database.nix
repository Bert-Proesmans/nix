{
  lib,
  pkgs,
  config,
  ...
}:
let
  postgresStatePath = "/var/lib/postgresql";
  postgresWalPath = "/var/lib/postgresql-wal";
  postgresSchemaVersion = config.services.postgresql.package.psqlSchema;
in
{
  ## Redis
  #
  # No special storage configuration or optimizations, this is a memory cache backed with a disk cache.

  ## Postgres
  #
  # Single database instance per host.
  # Locally accessible through unix sockets.
  # Split storage and write-ahead log (WAL) into separate datasets.

  # NOTE; We're providing the state parent directory! Inside are data directories per internal schema version (== PostgreSQL major version)
  # to not clobber data and make it easy for the administrator to migrate data manually to newer postgrs major versions.
  disko.devices.zpool.storage.datasets = {
    "postgres/host/state" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make single snapshot with "postgres/host/wal" !
      options.mountpoint = postgresStatePath;
    };

    "postgres/host/wal" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make single snapshot with "postgres/host/state" !
      options.mountpoint = postgresWalPath;
    };
  };

  services.postgresql = {
    enable = true;
    enableJIT = true;
    enableTCPIP = false;
    # ERROR; Postgres version is restricted due to extension compatibility with pgvecto.rs for Immich! Keep version at v16.
    # REF; https://github.com/tensorchord/pgvecto.rs/issues/607
    # REF; https://github.com/immich-app/immich/discussions/17025
    # REF; https://github.com/immich-app/immich/discussions/14280
    package = pkgs.postgresql_16;
    # NOTE; Create sub-directory for every major version to accomodate manual data migration.
    dataDir = "${postgresStatePath}/${postgresSchemaVersion}";
    initdbArgs = [
      # NOTE; Initdb will create the pg_wal directory as a symlink to the provided location.
      #
      # WARN; WAL is written to another filesystem to limit denial-of-service (DOS). This is precautionary measure while max_wall_size
      # and wal_buffers (aggregate wal filesize) and wal_level and max_replication_slots (standby mode) are unknown.
      "--waldir=${postgresWalPath}/${postgresSchemaVersion}"
      "--encoding=UTF8"
      # Sort in C, aka use straightforward byte-ordering
      "--no-locale" # Database optimization
      # NOTE; Database checksums disabled by default
    ];
    # ZFS Optimization
    settings.full_page_writes = "off";
  };

  systemd.services.postgresql = lib.mkIf config.services.postgresql.enable {
    environment.TZ = "Etc/UTC"; # Force native timezone aware data into UTC

    unitConfig.RequiresMountsFor = [
      postgresStatePath
      postgresWalPath
    ];
    serviceConfig = {
      StateDirectory = [
        "" # Reset
        (lib.removePrefix "/var/lib/" postgresStatePath)
        (lib.removePrefix "/var/lib/" config.services.postgresql.dataDir)
        #
        (lib.removePrefix "/var/lib/" postgresWalPath)
        (lib.removePrefix "/var/lib/" "${postgresWalPath}/${postgresSchemaVersion}")
      ];
    };
  };
}
