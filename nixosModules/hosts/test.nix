{ pkgs, config, ... }:
let
  state-postgres-dir = "/data/state-postgresql/${config.services.postgresql.package.psqlSchema}";
  wal-postgres-dir = "/data/wal-postgresql/${config.services.postgresql.package.psqlSchema}";
in
{
  networking.domain = "alpha.proesmans.eu";

  environment.systemPackages = [
    pkgs.socat
    pkgs.tcpdump
    pkgs.python3
    pkgs.nmap # ncat
  ];

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  services.postgresql = {
    enable = true;
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_15_jit;
    # Write directly into the data directory
    dataDir = state-postgres-dir;
    # dataDir = "/mnt/state/postgres/${config.services.postgresql.package.psqlSchema}";
    # Redirect initdb to empty directory, required because pg_wal is bindmounted into the state
    # directory and initdb doesn't like non-empty directories!
    #initdbArgs = [ "--waldir=/mnt/wal/postgres/${config.services.postgresql.package.psqlSchema}" ];
    settings.full_page_writes = "off";
  };

  systemd.tmpfiles.settings."10-postgres-ownership" = {
    # NOTE; Unix user for the postgres service is fixed to "postgres"
    "${state-postgres-dir}".d = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
    "${wal-postgres-dir}".d = {
      user = "postgres";
      group = "postgres";
      mode = "0700";
    };
  };

  system.stateVersion = "24.05";
}
