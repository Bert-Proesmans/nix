# Setup the Immich media management platform.
{ lib, pkgs, config, ... }: {
  environment.systemPackages = [
    pkgs.immich-cli
  ];

  services.immich = {
    enable = true;
    host = "127.175.0.1";
    port = 8080;
    openFirewall = false; # Use reverse proxy
    mediaLocation = "/storage/media/immich/originals";

    redis.enable = true;
    database = {
      enable = true;
      name = "immich";
      createDB = true;
    };

    environment = {
      IMMICH_LOG_LEVEL = "log";
      TZ = "Europe/Brussels"; # Used for interpreting timestamps without time zone
    };

    machine-learning = {
      enable = true;
      environment = {
        MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
        # Redirect temporary files to disk-backed temporary folder.
        TMPDIR = "/var/tmp";
      };
    };

    settings = {
      newVersionCheck.enabled = false;
      server.externalDomain = "https://photos.alpha.proesmans.eu";
      # TODO
    };
  };

  # @@ IMMICH media location @@
  # Immich expects a specific directory structure inside its state directory (UPLOAD_LOCATION)
  # "library" => Originals are stored here => main dataset
  # "profile" => Original profile images are stored here => main dataset
  # "thumbs" => re-encoded material => transcoded dataset
  # "encoded-video" => re-encoded material => transcoded dataset
  # "upload" => uploaded fragments => /var/tmp
  # "backups" => WHAT TO DO ?? <TODO>
  #
  # NOTE; Immich calculates free space from the filesystem where its state directory exists on.
  # The state directory will point to the storage pool dataset, and symlink will be written to other directory locations.
  systemd.tmpfiles.settings."immich-state" = {
    "/storage"."a+".argument = "group:immich:r-X";
    "/storage/media"."a+".argument = "group:immich:r-X";
    "/storage/media/immich"."A+".argument = "group:immich:r-X,default:group:immich:r-X";

    "/storage/media/immich/originals".z = {
      user = "immich";
      group = "immich";
      mode = "0700";
    };

    "/storage/media/immich/transcodes".z = {
      user = "immich";
      group = "immich";
      mode = "0700";
    };

    "/storage/media/immich/transcodes/thumbs".d = {
      user = "immich";
      group = "immich";
      mode = "0700";
      # age = null; # No automated cleanup !
    };

    "/storage/media/immich/transcodes/encoded-video".d = {
      user = "immich";
      group = "immich";
      mode = "0700";
      # age = null; # No automated cleanup !
    };

    "/storage/media/immich/originals/thumbs"."L+".argument = "/storage/media/immich/transcodes/thumbs";
    "/storage/media/immich/originals/encoded-video"."L+".argument = "/storage/media/immich/transcodes/encoded-video";
  };

  systemd.services.immich-server = lib.mkIf config.services.immich.enable {
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig.ReadWritePaths = [ "/storage/media/immich/originals" "/storage/media/immich/transcodes" ];
    unitConfig.RequiresMountsFor = [ "/storage/media/immich/originals" "/storage/media/immich/transcodes" ];

    serviceConfig.ExecStartPre =
      let
        script = pkgs.writeShellApplication {
          name = "symlink-uploads-directory-immich";
          runtimeInputs = [ pkgs.coreutils pkgs.util-linux ];
          # ERROR; Note the escaping of the dollar sign ($) when setting TARGET
          text = ''
            # ERROR; Must re-create the hidden immich file otherwise the server won't start
            TARGET="''${TMPDIR:-/var/tmp}"
            mkdir -p "$TARGET/upload" "$TARGET/backup"
            touch "$TARGET/upload/.immich" "$TARGET/backup/.immich"
            ln --symbolic --force "$TARGET/upload" "${config.services.immich.mediaLocation}/upload"
            ln --symbolic --force "$TARGET/backup" "${config.services.immich.mediaLocation}/backup" # DEBUG
          '';
        };
      in
      lib.getExe script;
  };

  disko.devices.zpool.storage.datasets = {
    # "media/immich" = { };
    "media/immich/originals" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/media/immich/originals";
      };
    };

    "media/immich/transcodes" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/media/immich/transcodes";
      };
    };
  };
}
