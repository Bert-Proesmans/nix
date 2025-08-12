{
  lib,
  pkgs,
  config,
  ...
}:
let
  immichStatePath = "/var/lib/immich";
  # ERROR; Immich machine learning service is already using '/var/cache/immich'
  immichCachePath = "/var/cache/immich-server";
  # Location for external libraries
  immichExternalStatePath = "/var/lib/immich-external";
in
{
  assertions =
    let
      # NOTE; This is supposed to throw an error if extension pgvecto-rs is missing.
      pgVectors = lib.findFirst (
        x: x.pname == "pgvecto-rs"
      ) null config.services.postgresql.finalPackage.installedExtensions;
    in
    [
      {
        assertion = (builtins.compareVersions pgVectors.version "0.4.0") == -1;
        message = ''
          Version of 'pgvecto-rs' must remain below 0.4.0, detected version is '${pgVectors.version}.
        '';
      }
    ];

  # @@ IMMICH media location @@
  # Immich expects a specific directory structure inside its state directory (immichStatePath == config.services.immich.mediaLocation)
  # "library" => Originals are stored here => main dataset
  # "profile" => Original profile images are stored here => main dataset
  # "thumbs" => re-encoded material => cache dataset
  # "encoded-video" => re-encoded material => cache dataset
  # "upload" => uploaded fragments => /var/tmp
  # "backups" => currently disabled, could mount a remote fs into this location one day
  #
  # NOTE; External libraries can be located anywhere, as long as the immich service user has read access. Prefer to make these location
  # read-only.
  #
  # NOTE; Immich calculates free space from the filesystem where its state directory exists on.
  # The state directory will point to the storage pool dataset, and symlinks will point to the other datasets.
  disko.devices.zpool.storage.datasets = {
    "media/immich/originals" = {
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = immichStatePath;
    };

    "media/immich/external" = {
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = immichExternalStatePath;
    };

    "media/immich/cache" = {
      type = "zfs_fs";
      # NOTE; Backup not necessary, can be regenerated
      options.mountpoint = immichCachePath;
    };
  };

  # Disable snapshots on the cache dataset
  services.sanoid.datasets."storage/media/immich/cache".use_template = [ "ignore" ];

  services.immich = {
    enable = true;
    host = "127.175.0.1";
    port = 8080;
    openFirewall = false; # Use reverse proxy
    mediaLocation = immichStatePath;
    accelerationDevices = [ "/dev/dri/renderD128" ];

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

        # ERROR; Huggingface library doing something fucky wucky producing the following error message
        # RuntimeError: Data processing error: I/O error: Operation not permitted (os error 1)
        #
        # Put all relevant filepaths together on the same filesystem so atomic move operations won't fail.
        HF_HOME = "/var/cache/immich/hf";
      };
    };

    settings = {
      backup.database.enabled = false;
      ffmpeg = {
        accel = "vaapi";
        accelDecode = true;
        preferredHwDevice = "renderD128"; # /dev/dri node
        cqMode = "auto"; # Attempt to "intelligently" apply constant quality mode factor
        targetAudioCodec = "aac"; # optimized for device compatibility
        targetResolution = "720"; # 720p, optimized for filesize
        targetVideoCodec = "hevc"; # optimized for device compatibility and size
        crf = 28; # Fidelity/Time factor, chosen for hevc, optimized for speed
        maxBitrate = "2800"; # kb/s absolute maximum for 720p (range 2000-4000)
        twoPass = true; # Transcode second pass optimized towards max bitrate (crf unused for hevc)

        transcode = "optimal"; # Transcode if above target resolution or non-accepted codec/container
        acceptedAudioCodecs = [
          "aac"
          "libopus"
        ];
        acceptedVideoCodecs = [
          "h264"
          "hevc"
          #"vp9" # Too new, optimized for device support
          #"av1" # Too new, optimized for device support
        ];
        acceptedContainers = [
          "mp4"
          "mov"
          #"ogg" # Apple support too recent, optimized for device support
          #"webm" # Too new (related to vp8/vp9/av1), optimized for device support
        ];
      };
      image.preview.size = 1080;
      library.scan.cronExpression = "0 2 * * 1"; # Monday 02:00 (@configured timezone)
      library.scan.enabled = true;
      logging.enabled = true;
      logging.level = "log";
      machineLearning.clip = {
        enabled = true;
        # Model optimized for good recall/time ratio in Dutch and English
        modelName = "ViT-B-16-SigLIP2__webli";
      };
      machineLearning.facialRecognition = {
        enabled = true;
        maxDistance = 0.45;
        minFaces = 5;
        # Changed model requires recognizing _all_ detected faces again (docs say restart face detection??)
        modelName = "buffalo_l"; # Default Immich v1.132+
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
        buttonText = "Login met Proesmans account";
        clientId = "photos";
        # Set placeholder value for secret, sops-template will replace this value at activation stage (secret decryption)
        clientSecret = config.sops.placeholder.immich-oauth-secret;
        defaultStorageQuota = 500;
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
      server.loginPageMessage = "Proesmans fotos, klik op de knop onderaan om verder te gaan";
      server.publicUsers = true;
      storageTemplate.enabled = true;
      # 2024/2024-12[-06][ Sinterklaas]/IMG_001.jpg
      storageTemplate.template = "{{y}}/{{y}}-{{MM}}{{#if dd}}-{{dd}}{{else}}{{/if}}{{#if album}} {{{album}}}{{else}}{{/if}}/{{{filename}}}";
      trash.days = 200;
      trash.enabled = true;
      user.deleteDelay = 30;
    };
  };

  # ERROR; Upstream did not make configuring oauth2 secrets composeable.
  # The immich configuration settings is configured as 'SOPS template'. At system activation, the placeholders inside the template
  # will be overwritten with secret values.
  sops.templates."immich-config.json" = {
    file = (pkgs.formats.json { }).generate "immich.json" config.services.immich.settings;
    owner = "immich";
    restartUnits = [ config.systemd.services.immich-server.name ];
  };

  systemd.services.immich-server = lib.mkIf config.services.immich.enable {
    environment = {
      # Force apply the configuration with overwritten secret data
      IMMICH_CONFIG_FILE = lib.mkForce config.sops.templates."immich-config.json".path;
      # Force overwrite custom URL for the machine learning service
      IMMICH_MACHINE_LEARNING_URL =
        let
          inherit (config.services.immich.machine-learning.environment) IMMICH_HOST IMMICH_PORT;
        in
        lib.mkForce "http://${IMMICH_HOST}:${IMMICH_PORT}";
    };

    unitConfig.RequiresMountsFor = [
      immichStatePath
      immichCachePath
      immichExternalStatePath
    ];
    serviceConfig = {
      SupplementaryGroups = [
        # Required for hardware accelerated video transcoding
        config.users.groups.render.name
      ];
      StateDirectory =
        assert immichStatePath == "/var/lib/immich";
        assert immichExternalStatePath == "/var/lib/immich-external";
        [
          "" # Reset
          "immich"
          "immich/library"
          "immich/profile"
          # External library location, make read-only
          "immich-external::ro"
        ];
      CacheDirectory =
        assert immichCachePath == "/var/cache/immich-server";
        [
          "" # Reset
          "immich-server"
          "immich-server/thumbs"
          "immich-server/encoded-video"
        ];
      ExecStartPre =
        let
          # There is no declarative way to configure the temporary directories. Also Immich expects full control over 'immichStatePath'
          # while its contents remain 100% persistent. Not all directory contents are fully persisted to optimize disk space usage.
          setupUploadsPath = pkgs.writeShellApplication {
            name = "setup-immich-uploads";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              # NOTE; Script must run as immich user!

              SOURCE="''${TMPDIR:-/var/tmp}"
              mkdir --parents "$SOURCE/upload"
              # ERROR; The hidden '.immich' file must exist/be recreated for every folder inside 'immichStatePath', this is part of
              # the immich startup check.
              touch "$SOURCE/upload/.immich"
              ln --symbolic --force "$SOURCE/upload" "${immichStatePath}/upload"
            '';
          };
          setupCachePath = pkgs.writeShellApplication {
            name = "setup-immich-cache";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              # NOTE; Script must run as immich user!

              SOURCE="${immichCachePath}"
              mkdir --parents "$SOURCE/{thumbs,encoded-video}"
              # ERROR; The hidden '.immich' file must exist/be recreated for every folder inside 'immichStatePath', this is part of
              # the immich startup check.
              touch "$SOURCE/{thumbs,encoded-video}/.immich"
              ln --symbolic --force "$SOURCE/thumbs" "${immichStatePath}/thumbs"
              ln --symbolic --force "$SOURCE/encoded-video" "${immichStatePath}/encoded-video"
            '';
          };
        in
        [
          (lib.getExe setupUploadsPath)
          (lib.getExe setupCachePath)
        ];
    };
  };
}
