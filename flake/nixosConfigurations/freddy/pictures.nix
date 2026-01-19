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

  ip-freddy = config.proesmans.facts.freddy.host.tailscale.address;
  fqdn-freddy = "freddy.omega.proesmans.eu";
in
{
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
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    openFirewall = false; # Use reverse proxy
    mediaLocation = immichStatePath;

    redis.enable = true;
    database = {
      enable = true;
      name = "immich";
      createDB = true;
      enableVectorChord = true; # New vector extension
      enableVectors = false; # Explicit disable, vectorchord is the current approach
    };

    environment = {
      TZ = "Europe/Brussels"; # Used for interpreting timestamps without time zone
      # Loopback address ranges are automatically added!
      #REF; https://expressjs.com/en/guide/behind-proxies.html
      # IMMICH_TRUSTED_PROXIES = ""; # Don't set when empty!

      # ERROR; Cannot initialise shaders for hardware acceleration without writeable home directory?
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] libva: VA-API version 1.22.0
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] libva: Trying to open /run/opengl-driver/lib/dri/radeonsi_drv_video.so
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] libva: Found init function __vaDriverInit_1_22
      # aug 16 21:10:29 buddy immich[1684]: Failed to create /var/empty/.cache for shader cache (Operation not permitted)---disabling.
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] libva: va_openDriver() returns 0
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] Initialised VAAPI connection: version 1.22
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] VAAPI driver: Mesa Gallium driver 25.2.0 for AMD Radeon Vega 3 Graphics (radeonsi, raven, ACO, DRM 3.61, 6.12.41).
      # aug 16 21:10:29 buddy immich[1684]: [AVHWDeviceContext @ 0x2a514e40] Driver not found in known nonstandard list, using standard behaviour.
      # HOME = "/var/cache/immich-server/home";
      # XDG_CACHE_HOME = "/var/cache/immich-server/home/.cache";
    };

    machine-learning = {
      enable = true;
      environment = {
        # ERROR; Matplotlib wants some kind of persistent cache
        # aug 16 23:03:17 buddy machine-learning[13288]: mkdir -p failed for path /var/empty/.config/matplotlib: [Errno 1] Operation not permitted: '/var/empty/.config'
        # aug 16 23:03:17 buddy machine-learning[13288]: Matplotlib created a temporary cache directory at /tmp/matplotlib-srvzammy because there was an issue with the default path (/var/empty/.config/matplotlib); it is highly recommended to set the MPLCONFIGDIR environment variable to a writable directory, in particular to speed up the import of Matplotlib and to better support multiprocessing.
        # HOME = "/var/cache/immich/home";
        # XDG_CONFIG_HOME = "/var/cache/immich/home/.config";
        # MPLCONFIGDIR = "/var/cache/immich/home/.config";
        # ERROR; Huggingface library doing something fucky wucky producing the following error message
        # RuntimeError: Data processing error: I/O error: Operation not permitted (os error 1)
        #
        # Put all relevant filepaths together on the same filesystem so atomic move operations won't fail.
        # HF_HOME = "/var/cache/immich/hf";
      };
    };

    settings = {
      backup.database.enabled = false;
      ffmpeg = {
        accel = "vaapi";
        accelDecode = true;
        # preferredHwDevice = "renderD128"; # /dev/dri node
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
      # machineLearning.urls = [ "http://127.175.0.99:3003" ];
      map.darkStyle = "https://tiles.immich.cloud/v1/style/dark.json";
      map.enabled = true;
      map.lightStyle = "https://tiles.immich.cloud/v1/style/light.json";
      newVersionCheck.enabled = false;
      # notifications.smtp = {
      #   enabled = true;
      #   from = "Pictures | Proesmans.eu <pictures@proesmans.eu>";
      #   replyTo = "pictures@proesmans.eu";
      #   transport = {
      #     host = fqdn-freddy;
      #     ignoreCert = false;
      #     username = "immich";
      #     password._secret = config.sops.secrets."immich-smtp".path;
      #     port = config.proesmans.facts.freddy.service.mail.port; # TLS ON
      #     secure = true; # TLS ON
      #   };
      # };
      # oauth = {
      #   enabled = true;
      #   autoRegister = true;
      #   buttonText = "Login met Proesmans account";
      #   clientId = "photos";
      #   # Set placeholder value for secret, sops-template will replace this value at activation stage (secret decryption)
      #   clientSecret._secret = config.sops.secrets."immich-oauth-secret".path;
      #   defaultStorageQuota = 500;
      #   # ERROR; OpenID specification does not allow redirects for openid-configuration endpoint!
      #   # It's also unspecified that redirects are accepted on other defined endpoints eg, /token, /userinfo
      #   # issuerUrl = "https://idm.proesmans.eu/oauth2/openid/photos/.well-known/openid-configuration";
      #   issuerUrl = "https://alpha.idm.proesmans.eu/oauth2/openid/photos/.well-known/openid-configuration";
      #   mobileOverrideEnabled = false;
      #   mobileRedirectUri = "";
      #   profileSigningAlgorithm = "none";
      #   scope = "openid email profile";
      #   signingAlgorithm = "RS256";
      #   # NOTE; Immich currently ONLY applies these claims during account creation!
      #   # ERROR; storage label _must_ be unique for each user (or unset)!
      #   # Trying to group media from multiple users behind the same label is a wrong assumption.
      #   storageLabelClaim = "preferred_username";
      #   storageQuotaClaim = "immich_quota";
      # };
      # passwordLogin.enabled = false;
      passwordLogin.enabled = true; # Enable for maintenance work
      reverseGeocoding.enabled = true;
      server.externalDomain = "https://pictures.proesmans.eu";
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

  disko.devices.zpool.zroot.datasets = {
    "encryptionroot/media/local-immich" = {
      type = "zfs_fs";
      options.mountpoint = "/var/lib/local-immich";
      options.refquota = "10G";
    };
  };

  systemd.mounts = [
    {
      description = "Immich state directory";
      wants = [ ];
      after = [ ];

      # NOTE; Local cache, followed by networked storage
      what = "/var/lib/local-immich:/mnt/buddy/pictures";
      where = "/var/lib/immich";
      type = "fuse.mergerfs";
      options = lib.concatStringsSep "," [
        # NOTE; I'm not caring about path transformation into specific mount, nor (tricky) behaviour on rename etc.
        # The purpose of mergerfs is to keep immich alive when the sftp mount hangs/fails(network unavailability).
        # This setup is flexible enough to add additional storage later.
        #
        # WARN; The reported free space is the aggregate space available not the contiguous space available.
        #
        # REF; https://manpages.debian.org/buster/mergerfs/mergerfs.1.en.html#mount_options
        "fsname=immich mergerfs"
        "defaults" # atomic_o_trunc, auto_cache, big_writes, default_permissions, splice_move, splice_read, splice_write
        "allow_other"
        "moveonenospc=true" # Retry with other mount if write fails
        "use_ino"
        "hard_remove" # Improve data consistency
        "dropcacheonclose=true"
        "minfreespace=1M" # 1 megabyte, intention is to fill the first mount entirely!
        "category.create=ff" # Create files on first mount (local disk)
        "category.search=ff" # Search files on first mount (local disk)
      ];
      unitConfig = {
        RequiresMountsFor = [ "/var/lib/local-immich" ];
        WantsMountsFor = [ "/mnt/buddy/pictures" ];
      };
      mountConfig.TimeoutSec = 30;
    }
  ];

  systemd.automounts = [
    {
      # Since /var/lib/immich is not part of local-fs, add an automount so it gets ordered between services anyway.
      description = "Automount for /var/lib/immich";
      wantedBy = [ "multi-user.target" ];
      where = "/var/lib/immich";
    }
  ];

  environment.systemPackages = [
    pkgs.fuse3 # fuse defaults to fuse2
    pkgs.mergerfs-tools
    pkgs.mergerfs
  ];

  services.nginx.virtualHosts."omega.pictures.proesmans.eu" = {
    serverAliases = [ "pictures.proesmans.eu" ];
    useACMEHost = "omega-services.proesmans.eu";
    onlySSL = true;
    locations."/" = {
      proxyPass =
        assert config.services.immich.host == "127.0.0.1";
        "http://127.0.0.1:${toString config.services.immich.port}";
      proxyWebsockets = true;
    };
    extraConfig = ''
      # allow large file uploads
      client_max_body_size 15G;

      # disable buffering uploads to prevent OOM on reverse proxy server and make uploads twice as fast (no pause)
      proxy_request_buffering off;

      # increase body buffer to avoid limiting upload speed
      client_body_buffer_size 1024k;

      # increase timeouts for large uploads
      proxy_read_timeout 10m; # Wait on upstream
      proxy_send_timeout 10m; # Wait on client
      send_timeout       1h; # Websocket tunnel timeouts
    '';
  };

  systemd.services.immich-server = lib.mkIf config.services.immich.enable {

    serviceConfig = {
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

              TEMP="''${TMPDIR:-/var/tmp}"
              mkdir --parents "$TEMP/upload"
              # ERROR; The hidden '.immich' file must exist/be recreated for every folder inside 'immichStatePath', this is part of
              # the immich startup check.
              touch "$TEMP/upload/.immich"
              ln --symbolic --force --target-directory="${immichStatePath}" "$TEMP/upload"
            '';
          };
        in
        [
          (lib.getExe setupUploadsPath)
        ];
    };

    unitConfig.RequiresMountsFor = [
      immichStatePath
      immichCachePath
      immichExternalStatePath
    ];
  };
}
