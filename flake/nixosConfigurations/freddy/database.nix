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
in
{
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
}
