{ lib, pkgs, flake, config, ... }: {
  imports = [ ./WIP.nix ];

  networking.domain = "alpha.proesmans.eu";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    mediaLocation = "/var/lib/immich";

    environment = {
      IMMICH_LOG_LEVEL = "log";
      # The timezone used for interpreting date/timestamps without time zone indicator
      TZ = "Europe/Brussels";
      IMMICH_CONFIG_FILE = "/run/credentials/immich-server.service/CONFIG";
    };

    machine-learning = {
      environment = {
        MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
        # Attempt to redirect temporary files to disk-backed temporary folder.
        # /var/temp is backed by a persisted volume.
        TMPDIR = "/var/tmp";
      };
    };
  };

  systemd.services.immich-server = {
    # NOTE; Immich wants a specific directory structure inside its state directory (UPLOAD_LOCATION)
    # "library" => Originals are stored here => main dataset
    # "profile" => Original profile images are stored here => main dataset
    # "thumbs" => re-encoded material => transcoded dataset
    # "encoded-video" => re-encoded material => transcoded dataset
    # "upload" => uploaded fragments => /var/temp
    #
    # NOTE; Since immich calculates free space from the filesystem where its state directory exists on
    # we bind mount the main dataset at /var/lib/immich, and symlink in the other datasets
    serviceConfig.StateDirectory = [
      "transcodes-immich"
      "transcodes-immich/thumbs:immich/thumbs"
      "transcodes-immich/encoded-video:immich/encoded-video"
    ];

    serviceConfig.ExecStartPre =
      let
        script = pkgs.writeShellApplication {
          name = "symlink-uploads-directory-immich";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            ln --symbolic --force /var/tmp "${config.services.immich.mediaLocation}/upload"
          '';
        };
      in
      lib.getExe script;

    serviceConfig.LoadCredential = [
      # WARN; Config file must be loaded into the unit credential store because
      # the original files require root access. This unit executes with user immich permissions.
      "CONFIG:${config.microvm.suitcase.secrets."immich-config.json".path}"
    ];
  };

  services.postgresql = {
    enableJIT = true;
    enableTCPIP = false;
    package = pkgs.postgresql_15_jit;
    initdbArgs = [
      # NOTE; Initdb will create the pg_wal directory as a symlink to the provided location.
      #
      # WARN; WAL is written to another filesystem to limit denial-of-service (DOS) when clients open
      # transactions for a long time.
      "--waldir=/var/lib/wal-postgresql/${config.services.postgresql.package.psqlSchema}"
      "--encoding=UTF8"
      # Sort in C, aka use straightforward byte-ordering
      "--no-locale" # Database optimization
    ];
    # ZFS Optimization
    settings.full_page_writes = "off";
  };

  systemd.services.postgresql.serviceConfig = {
    StateDirectory = [ "wal-postgresql wal-postgresql/${config.services.postgresql.package.psqlSchema}" ];
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
