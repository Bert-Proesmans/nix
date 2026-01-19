{
  lib,
  pkgs,
  config,
  ...
}:
let
  mariadbStatePath = "/var/lib/mysql";
  mariadbWalPath = "/var/lib/mysql-wal";
  mariadbSchemaVersion = lib.versions.major config.services.mysql.package.version;

  postgresStatePath = "/var/lib/postgresql";
  postgresWalPath = "/var/lib/postgresql-wal";
  postgresSchemaVersion = config.services.postgresql.package.psqlSchema;
in
{
  ## Redis
  #
  # No special storage configuration or optimizations, this is a memory cache backed with a disk cache.

  ## Mysql
  #
  # Dedicated dataset for this database, shared service for all services requiring mariadb access.
  disko.devices.zpool.zroot.datasets = {
    "encryptionroot/mysql/host/state" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make atomic snapshot with "encryptionroot/mysql/host/wal" !
      options.mountpoint = mariadbStatePath;
      options.refquota = "2G";
    };

    "encryptionroot/mysql/host/wal" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make atomic snapshot with "encryptionroot/mysql/host/state" !
      options.mountpoint = mariadbWalPath;
      # The block size of the log/WAL files is 4096 bytes!
      # The recordsize is set to match the application because we're using virtual disks.
      # REF; https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-system-variables#innodb_log_file_size
      options.recordsize = "4K";
      options.refquota = "1G";
    };
  };

  services.mysql = {
    enable = true;
    package = pkgs.mariadb_118;
    # NOTE; Create sub-directory for every major version to accomodate manual data migration.
    dataDir = lib.strings.normalizePath "${mariadbStatePath}/${mariadbSchemaVersion}";
    settings.mariadb = {
      # NOTE; The settings below do not work in the "general" mysqld section.
      enforce_storage_engine = "InnoDB";
      default_storage_engine = "InnoDB";
    };
    settings.mysqld = {
      # Innodb start directory is derived from mysql dataDir
      # innodb_data_home_dir = <dataDir>;
      # Location of WAL files
      innodb_log_group_home_dir = lib.strings.normalizePath "${mariadbWalPath}/${mariadbSchemaVersion}";
      innodb_undo_directory = lib.strings.normalizePath "${mariadbWalPath}/${mariadbSchemaVersion}";

      # Perform proper shutdown that allows for offline major upgrade of datafiles
      innodb_fast_shutdown = 1;
      innodb_read_io_threads = 4; # default, unrelated to system resources
      innodb_write_io_threads = 4; # default, unrelated to system resources
      innodb_buffer_pool_size = "1G"; # Minimum 1G
      # innodb_buffer_pool_instances = 1; Removed config

      # ERROR; Option looks not-settable/hardcoded?
      # innodb_log_write_ahead_size=16384;
      # ERROR; Disabling checksums is removed and not allowed
      # innodb_innodb_checksum_algorithm = "none"; # ZFS checksums already
      innodb_doublewrite = 0; # ZFS does atomic writes already
      # This is an optimization for hard disks to amortize the seek time. Not relevant on ZFS.
      innodb_flush_neighbors = 0;
      innodb_flush_method = "fsync"; # ZFS doesn't support O_DIRECT
      innodb_use_native_aio = 0; # ZFS not yet ready for direct IO
      innodb_use_atomic_writes = 0; # ZFS not yet ready for direct IO
    };
  };

  systemd.services.mysql = lib.mkIf config.services.mysql.enable {
    environment.TZ = "Etc/UTC"; # Force native timezone aware data into UTC

    unitConfig.RequiresMountsFor = [
      "" # Reset
      mariadbStatePath
      mariadbWalPath
    ];

    serviceConfig = {
      StateDirectory =
        assert mariadbStatePath == "/var/lib/mysql";
        assert mariadbWalPath == "/var/lib/mysql-wal";
        [
          "" # Reset
          "mysql"
          "mysql/${mariadbSchemaVersion}"
          "mysql-wal"
          "mysql-wal/${mariadbSchemaVersion}"
        ];
      StateDirectoryMode = "0700";
    };
  };

  ## Postgres
  #
  # Dedicated dataset(s) per database inside host+virtual machines. This configuration module only concerns itself with the
  # database server on the host.
  # Locally accessible through unix sockets.
  # Split storage and write-ahead log (WAL) into separate datasets.

  # NOTE; We're providing the state parent directory! Inside are data directories per internal schema version (== PostgreSQL major version)
  # to not clobber data and make it easy for the administrator to migrate data manually to newer postgrs major versions.
  disko.devices.zpool.zroot.datasets = {
    "encryptionroot/postgres/host/state" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make atomic snapshot with "postgres/host/wal" !
      options.mountpoint = postgresStatePath;
      options.refquota = "20G";
    };

    "encryptionroot/postgres/host/wal" = {
      type = "zfs_fs";
      # WARN; To be backed up ! Make atomic snapshot with "postgres/host/state" !
      options.mountpoint = postgresWalPath;
      options.refquota = "2G";
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
      StateDirectory =
        assert postgresStatePath == "/var/lib/postgresql";
        assert postgresWalPath == "/var/lib/postgresql-wal";
        [
          "" # Reset
          "postgresql"
          "postgresql/${postgresSchemaVersion}"
          "postgresql-wal"
          "postgresql-wal/${postgresSchemaVersion}"
        ];
      # NOTE(2025-12-02); I don't remember why I set this explicitly, causes conflicting definition now.
      # StateDirectoryMode = "0700";
    };
  };
}
