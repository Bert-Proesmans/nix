# Setup the Immich media management platform.
{ lib, pkgs, config, ... }:
let
  json-convert = pkgs.formats.json { };
in
{
  environment.systemPackages = [
    pkgs.immich-cli
  ];

  sops.templates."immich-config.json" = {
    file = json-convert.generate "immich.json" config.services.immich.settings;
    owner = "immich";
    restartUnits = [ config.systemd.services.immich-server.name ];
  };

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

    environment.TZ = "Europe/Brussels"; # Used for interpreting timestamps without time zone

    machine-learning = {
      enable = true;
      environment = {
        IMMICH_HOST = lib.mkForce "127.175.0.99"; # Upstream overwrite
        IMMICH_PORT = lib.mkForce "3003"; # Upstream overwrite
        MACHINE_LEARNING_CACHE_FOLDER = "/var/cache/immich";
        # Redirect temporary files to disk-backed temporary folder.
        TMPDIR = "/var/tmp";
      };
    };

    settings = {
      backup.database.enabled = false;
      ffmpeg = {
        accel = "disabled";
        acceptedAudioCodecs = [ "aac" "libopus" ];
        acceptedVideoCodecs = [ "h264" "av1" ];
      };
      image.preview.size = 1080;
      library.scan.cronExpression = "0 2 * * 1";
      library.scan.enabled = true;
      logging.enabled = true;
      logging.level = "log";
      machineLearning.facialRecognition = {
        enabled = true;
        maxDistance = 0.45;
        minFaces = 5;
      };
      machineLearning.urls = [ "http://127.175.0.99:3003" ];
      map.darkStyle = "https://tiles.immich.cloud/v1/style/dark.json";
      map.enabled = true;
      map.lightStyle = "https://tiles.immich.cloud/v1/style/light.json";
      newVersionCheck.enabled = false;
      notifications.smtp.enabled = false;
      oauth = {
        enabled = true;
        autoRegister = true;
        buttonText = "Login with proesmans account";
        clientId = "photos";
        # Set placeholder value for secret, sops-template will replace this value at activation stage (secret decryption)
        clientSecret = config.sops.placeholder.immich-oauth-secret;
        defaultStorageQuota = 100;
        issuerUrl = "https://alpha.idm.proesmans.eu/oauth2/openid/photos/.well-known/openid-configuration";
        mobileOverrideEnabled = false;
        mobileRedirectUri = "";
        profileSigningAlgorithm = "none";
        scope = "openid email profile";
        signingAlgorithm = "RS256";
        # NOTE; Immich currently ONLY applies these claims during account creation!
        storageLabelClaim = "immich_label";
        storageQuotaClaim = "immich_quota";
      };
      passwordLogin.enabled = true;
      reverseGeocoding.enabled = true;
      server.externalDomain = "https://photos.alpha.proesmans.eu";
      server.loginPageMessage = "Proesmans Photos system, proceed by clicking the button at the bottom";
      server.publicUsers = true;
      storageTemplate.enabled = true;
      # 2024/2024-12[-06][ Sinterklaas]/IMG_001.jpg
      storageTemplate.template = "{{y}}/{{y}}-{{MM}}{{#if dd}}-{{dd}}{{else}}{{/if}}{{#if album}} {{{album}}}{{else}}{{/if}}/{{{filename}}}";
      trash.days = 200;
      trash.enabled = true;
      user.deleteDelay = 30;
    };
  };

  # @@ IMMICH media location @@
  # Immich expects a specific directory structure inside its state directory (UPLOAD_LOCATION)
  # "library" => Originals are stored here => main dataset
  # "profile" => Original profile images are stored here => main dataset
  # "thumbs" => re-encoded material => transcoded dataset
  # "encoded-video" => re-encoded material => transcoded dataset
  # "upload" => uploaded fragments => /var/tmp
  # "backups" => currently disabled, could mount a remote fs into this location one day
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

  systemd.tmpfiles.settings."immich-external-libraries" = {
    # TODO
  };

  systemd.services.immich-server = lib.mkIf config.services.immich.enable {
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];

    # Overwrite the upstream config file creation with sops templating.
    # Upstream did not make configuring oauth2 secrets composeable.
    environment.IMMICH_CONFIG_FILE = lib.mkForce config.sops.templates."immich-config.json".path;

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
