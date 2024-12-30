# Provide a single common database for services.
{ lib, pkgs, config, ... }:
let
  state_pg = "/storage/postgres/state/central/${config.services.postgresql.package.psqlSchema}";
  wal_pg = "/storage/postgres/wal/central/${config.services.postgresql.package.psqlSchema}";
in
{
  services.postgresql = {
    enable = true;
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_16; # Adds/removes _jit depending on value of "enableJIT"
    dataDir = state_pg;
    initdbArgs = [
      # NOTE; Initdb will create the pg_wal directory as a symlink to the provided location.
      #
      # WARN; WAL is written to another filesystem to limit denial-of-service (DOS) when clients open
      # transactions for a long time.
      "--waldir=${wal_pg}"
      "--encoding=UTF8"
      # Sort in C, aka use straightforward byte-ordering
      "--no-locale" # Database optimization
    ];
    # ZFS Optimization
    settings.full_page_writes = "off";
  };

  systemd.tmpfiles.settings."postgres-state" = {
    "/storage"."a+".argument = "group:postgres:r-X"; # group hardcoded
    "/storage/postgres"."A+".argument = "group:postgres:r-X,default:group:postgres:r-X"; # group hardcoded

    "${state_pg}".d = {
      user = "postgres"; # Hardcoded
      group = "postgres"; # Hardcoded
      mode = "0750";
      # age = null; # No automated cleanup !
    };

    "${wal_pg}".d = {
      user = "postgres"; # Hardcoded
      group = "postgres"; # Hardcoded
      mode = "0750";
      # age = null; # No automated cleanup !
    };
  };

  systemd.services.postgresql = lib.mkIf config.services.postgresql.enable {
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    environment.TZ = "Etc/UTC";
    serviceConfig.ReadWritePaths = [ state_pg wal_pg ];
    # Upstream configuration uses value type 'string' instead of list, so must force override value.
    unitConfig.RequiresMountsFor = lib.mkForce [ state_pg wal_pg ];
  };

  disko.devices.zpool.storage.datasets = {
    "postgres/state/central" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/postgres/state/central"; # Hardcoded
      };
    };
    "postgres/wal/central" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/postgres/wal/central"; # Hardcoded
      };
    };
  };
}
