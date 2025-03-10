{ lib, pkgs, config, ... }: {
  imports = [ ./WIP.nix ];

  networking.domain = "alpha.proesmans.eu";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  # Immich crashes when rebinding AF_INET to AF_VSOCK
  # REF; https://github.com/kohlschutter/unsock/issues/3
  #
  # The code itself doesn't support binding to other types of sockets.
  proesmans.vsock-proxy.proxies = [{
    description = "Connect VSOCK to AF_INET for immich service";
    listen.vsock.cid = -1; # Binds to localhost
    listen.port = 8080;
    transmit.tcp.ip = config.services.immich.host;
    transmit.port = config.services.immich.port;
  }];

  # nixpkgs.overlays = [
  #   (final: prev:
  #     let
  #       machine-learning-upstream = prev.immich.passthru.machine-learning;
  #     in
  #     {
  #       immich = prev.unsock.wrap (prev.immich.overrideAttrs (old: {
  #         # WARN; Assume upstream has properly tested for quicker build completion
  #         doCheck = false;
  #         passthru = old.passthru // {
  #           # ERROR; 'Immich machine learning' is pulled from the passed through property of 'Immich'
  #           machine-learning = final.immich-machine-learning;
  #         };
  #       }));
  #       # immich-machine-learning = prev.unsock.wrap (prev.immich-machine-learning.overrideAttrs (old: {
  #       #   # WARN; Assume upstream has properly tested for quicker build completion
  #       #   doCheck = false;
  #       # }));
  #       immich-machine-learning = prev.unsock.wrap (machine-learning-upstream.overrideAttrs (old: {
  #         # WARN; Assume upstream has properly tested for quicker build completion
  #         doCheck = false;
  #       }));
  #     })
  # ];

  services.immich = {
    enable = true;
    host = "127.175.0.0";
    port = 8080;
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

    unsock = {
      enable = false;
      tweaks.accept-convert-vsock = true;
      proxies = [
        {
          match.port = config.services.immich.port;
          to.vsock.cid = -1; # Bind to loopback
          to.vsock.port = 8080;
        }
        # NOTE; No proxy for machine learning, i don't care if both server modules talk to each other
        # over loopback AF_INET
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];
    };
  };

  systemd.services.immich-machine-learning = {
    unsock = {
      enable = false;
      socket-directory = config.systemd.services.immich-server.unsock.socket-directory;
      tweaks.accept-convert-vsock = true;
      proxies = [
        {
          match.port = config.services.immich.port;
          to.vsock.cid = -1; # Bind to loopback
          to.vsock.port = 8080;
        }
        # NOTE; No proxy for machine learning, i don't care if both server modules talk to each other
        # over loopback AF_INET
      ];
    };

    serviceConfig = {
      # ERROR; Must manually open up the usage of VSOCKs.
      RestrictAddressFamilies = [ "AF_VSOCK" ];
    };
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
