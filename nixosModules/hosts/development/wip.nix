{ pkgs, config, ... }: {
  # state-postgres-dir = "/data/db/state/${config.services.postgresql.package.psqlSchema}";
  # wal-postgres-dir = "/data/db/wal/${config.services.postgresql.package.psqlSchema}";

  # services.postgresql = {
  #   enable = false;
  #   enableJIT = true;
  #   enableTCPIP = false;
  #   package = pkgs.postgresql_15_jit;
  #   # Write directly into the data directory
  #   dataDir = "/mnt/state/postgres/${config.services.postgresql.package.psqlSchema}";
  #   # Redirect initdb to empty directory, required because pg_wal is bindmounted into the state
  #   # directory and initdb doesn't like non-empty directories!
  #   initdbArgs = [ "--waldir=/mnt/wal/postgres/${config.services.postgresql.package.psqlSchema}" ];
  #   settings.full_page_writes = "off";
  # }; 
}
