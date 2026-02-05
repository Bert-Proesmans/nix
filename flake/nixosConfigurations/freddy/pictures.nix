{
  lib,
  utils,
  pkgs,
  config,
  ...
}:
let
  immichStatePath = "/var/lib/immich";
  # Location for media while storage node is offline
  immichVPSOnlineStoragePath = "/var/lib/local-immich";
  # Location for external libraries
  immichExternalStatePath = "/var/lib/immich-external";

  ip-freddy = config.proesmans.facts.freddy.host.tailscale.address;
  fqdn-freddy = "freddy.omega.proesmans.eu";
in
{

  disko.devices.zpool.zroot.datasets = {
    "encryptionroot/media/local-immich" = {
      type = "zfs_fs";
      options.mountpoint = "/var/lib/local-immich";
      options.refquota = "10G";
    };
  };

  systemd.tmpfiles.settings."10-immich" = {
    "/var/lib/immich" = {
      d = {
        # REF; https://wiki.archlinux.org/title/SFTP_chroot#Setup_the_filesystem
        user = "root";
        group = "root";
        mode = "0000";
      };
      # ERROR; Cannot use systemd-tmpfiles to coordinate fsattributes before mounting!
      # Must apply immutable attribute manually!
      # h.argument = "i"; # Immutable (chattr)
    };
  };

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
        HOME = "/var/cache/immich/home";
        XDG_CONFIG_HOME = "/var/cache/immich/home/.config";
        MPLCONFIGDIR = "/var/cache/immich/home/.config";
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

  systemd.mounts = [
    {
      description = "Immich state directory";
      conflicts = [ "umount.target" ];
      after = [ "network.target" ];

      # NOTE; Local cache, followed by networked storage
      # 'RW' means read-write, 1M is the individual minfreespace option on the subject branch
      # 'NC' means no-create on the subject branch
      #
      # NOTE; Minimum free space is set larger than a single picture as to not run out of space halfway writing.
      what = "${immichVPSOnlineStoragePath}=RW,10M:/mnt/remote/buddy-sftp/pictures=NC";
      where = "/var/lib/immich";
      # Currently experimenting with mergerFS, I might be holding it wrong..
      # READ THE DOCS; https://trapexit.github.io/mergerfs/latest/quickstart/
      #
      # ERROR; mergerfs is sadly way more unstable than anticipated.
      # The first hour of experimenting causes system hangs where each process doing _anything_ filesystem related are being blocked.
      # Consistent reproduction happens when running `sudo ls -la /var/lib/immich`, while the command without sudo _just works_ --'
      # Targetted file work, like immich who has a file reference database, seems to work without any issues.
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
        # "allow_other" # Implied when mount is executed as root
        "category.create=ff" # Write always to first found RW-branch
        "cache.files=off" # Prevent buffer bloat, increase performance
        # Return the newest modified time when applications call mtime().
        # WARN; This is an exception on the search category policy 'ff'.
        "func.getattr=newest"
        # Increased size of messages communicated over /dev/fuse, directly increases memory usage.
        # Optimized value from mergerFS docs.
        "fuse-msg-size=4M"
        "func.readdir=cor" # Optimize directory listing over high latency network mounts
        # Retry with other mount if write fails
        # NOTE; Only useful with multiple writeable branches..
        # "moveonenospc=true"
      ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [ immichVPSOnlineStoragePath ];
        # ERROR; Attempting to load the sftp mount while the host is offline could lead to system hangs!
        # DO NOT _just_ depend on the rclone mount without specialized reason!
        # WantsMountsFor = [ "<buddy-pictures>" ];
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

  systemd.tmpfiles.settings."10-immich-links" = {
    "${immichExternalStatePath}"."L+" = {
      # Link into remote mounted storage
      #
      # ERROR; Since this is a link, all path elements must be accessible by the immich user!
      argument = "/mnt/remote/buddy-sftp/pictures-external";
    };
  };

  systemd.services.immich-server = lib.mkIf config.services.immich.enable {
    wantedBy = lib.mkForce [ ]; # DEBUG
    serviceConfig = {
      # NOTE; Immich state layout contains links into temporary directory
      PrivateTmp = true;

      StateDirectory =
        assert immichStatePath == "/var/lib/immich";
        # TODO; Figure out how to read-lock 'immichVPSOnlineStoragePath'
        assert immichVPSOnlineStoragePath == "/var/lib/local-immich";
        [
          "immich/library"
          "immich/profile"
          # Online media cache directory. Added here to simplify file permissions.
          "local-immich"
        ];
      # Prevent others from peeping into the data
      StateDirectoryMode = "0750";

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
              # Create link "${immichStatePath}/upload" pointing to "$TEMP/upload"
              ln --symbolic --force --no-target-directory "$TEMP/upload" "${immichStatePath}/upload"
            '';
          };
        in
        [
          # WARN; Temporary directory access required!
          (lib.getExe setupUploadsPath)
        ];
    };

    unitConfig.RequiresMountsFor = [
      immichStatePath
      immichVPSOnlineStoragePath
    ];
  };

  systemd.services.immich-move-data = {
    description = "Move Immich media";
    # Need these units but won't queue a startjob if they aren't active
    requisite = [
      # Both of these units combined active are precondition for the mover script
      config.systemd.targets."buddy-online".name
      "${utils.escapeSystemdPath "/mnt/remote/buddy-sftp"}.mount"
    ];
    after = [
      config.systemd.targets."buddy-online".name
    ];
    # startAt = "<TODO>";
    path = [
      pkgs.mergerfs-tools # mergerfs.balance
      pkgs.rsync
      pkgs.findutils # find
    ];
    enableStrictShellChecks = true;
    script = ''
      ###
      # Assumes storage is mounted and available!
      #
      # NOTE; The mount unit can be active but not functional, this is because rclone keeps a cache alive to not cause dataloss
      # on abrubt disconnect of buddy.
      ###

      # NOTE; More branches will require some type of disk usage balancing.
      # eg; mergerfs.balance "$immich_state_path" (BUT this is not a perfect match for use-case)
      source_path="/var/lib/local-immich"
      target_path="/mnt/remote/buddy-sftp/pictures"
      rsync ${
        lib.concatStringsSep " " [
          "--compress" # Attempt to transfer less bits
          "--itemize-changes" # Print details of files transferred
          "--archive"
          "--one-file-system" # Stick to a single filesystem to discover files in <source>
          "--links"
          "--hard-links"
          "--acls"
          "--xattrs"
          "--executability"
          "--delay-updates" # Atomic file renames
          "--whole-file" # Don't attempt to retry interrupted transfers
          # I want to cleanup partial files after failure, those are seen as double occurences of the same file
          # "--partial"
          "--partial-dir=.rsync-partial"
          "--relative"
          "--remove-source-files"

          # SOURCE
          # Manually include the directories to sync over
          "\"$source_path\"/./{encoded-video,library,profile,thumbs}"

          # DESTINATION
          # WARN; Destination must end with a slash!
          "$target_path/"
        ]
      }

      # WARN; rsync doesn't clean-up empty directories!
      # WARN; mindepth=1 to not delete the toplevel directories themselves!
      find "$source_path/"{encoded-video,library,profile,thumbs} -mindepth 1 -type d -empty -delete
    '';
  };
}
