{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Use this path to store the wine state data
  winePrefix = "/storage/backup/backblaze/wineprefix";

  backblaze-wine-environment = pkgs.proesmans.backblaze-wine-environment.override ({
    inherit winePrefix;
    # Add these packages to the share library path
    libraries = [
      pkgs.freetype # FreeType for Wine
      pkgs.virtualglLib # VirtualGL libs (vglrun)
      pkgs.pkgsi686Linux.virtualglLib # 32-bit VirtualGL libs (vglrun)
    ];
  });
in
{
  # GPU/Graphics configuration
  programs.turbovnc.ensureHeadlessSoftwareOpenGL = true;
  hardware.graphics.enable32Bit = true;

  environment.variables.LD_LIBRARY_PATH = [
    "/run/opengl-driver-32/lib" # 32-bit for wine
  ];

  # Configure session file that's being called by turbovnc
  # Use session filename "none+ratpoison" (none = desktop manager, ratpoison = window manager)
  # ERROR; The package is configured with another
  # Ratpoison finds its system-wide configuration file at {prefix}/etc, this must be changed with build flags, see
  # `nixpkgs.overlays` below.
  services.xserver.windowManager.ratpoison.enable = true;

  environment.etc."ratpoisonrc".text = ''
    echo Ratpoison started
    set border 1
    exec ${lib.getExe backblaze-wine-environment}    
    echo WINE environment started
    # quit
  '';

  users.users.backblaze = {
    # Normal user for opening shell and assuming identity
    isNormalUser = true;
    group = "backblaze";
    extraGroups = [ "vglusers" ];
    useDefaultShell = true;
  };
  users.groups.backblaze = { };

  systemd.targets.backblaze-backup = {
    wantedBy = [ "graphical.target" ];
  };

  systemd.services.backblaze-backup = {
    enable = true;
    description = "TurboVNC wrapped backblaze personal backup";
    wantedBy = [ config.systemd.targets.backblaze-backup.name ];
    partOf = [ config.systemd.targets.backblaze-backup.name ];
    wants = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    upholds = [ config.systemd.services.display-manager.name ];
    restartTriggers = [ (config.environment.etc."ratpoisonrc".source or null) ];

    path = [
      pkgs.turbovnc
      pkgs.coreutils
      pkgs.mount
      pkgs.umount
      pkgs.gocryptfs
    ];
    # WARN; Various helper scripts try to be helpful by purging LD_LIBRARY_PATH/LD_PRELOAD_PATH etc,
    # some environment variables from bigger scopes do not trickle down! Only set necessary variables
    # in scope closest to where they're needed!
    environment.XSESSIONSDIR = "${config.services.displayManager.sessionData.desktops}/share/xsessions";
    enableStrictShellChecks = true;
    script = lib.strings.concatStringsSep " " [
      # -vgl argument activates virtualgl rendering and requires virtual gl on path
      # ERROR; Do not enable virtualgl for the entire window manager because that exhausts the available x-session connections.
      # Activate virtualgl _per application_ instead.
      #
      "vncserver"
      "-fg"
      "-autokill"
      "-geometry 1240x900"
      # NOTE; No security on the vnc server + only accept connections from localhost.
      # Use openId security instead at the proxy level!
      "-securitytypes none -localhost"
      "-xstartup ${
        lib.getExe (
          pkgs.writeShellApplication {
            name = "xstartup.turbovnc";
            runtimeInputs = [
              pkgs.gnugrep
              pkgs.gnused
              pkgs.virtualgl
            ];
            text = builtins.readFile ./xstartup-turbovnc.sh;
          }
        )
      }"
      # IMPORTANT; Set this to the desktopManager+windoManager combo configured through the xserver options.
      # SEEALSO; `services.xserver.windowManager.<name>.enable` above
      "-wm 'none+ratpoison'"
      "-depth 24"
      # NOTE; Only one active connection active at a time and force disconnect the other
      "-nevershared -disconnect"
      # -nointerframe disables calculating interframe distances
      # NOTE; Saves cpu but increases bandwidth usage in case client applications performs runaway amount of draws
      "-nointerframe"
    ];

    preStart = ''
      # Source directory before overlays
      # WARN; Contains bind mounts!
      VAULT="/storage/backup/backblaze/drive_d/paths"

      # Target drive for WINE
      DRIVE="/storage/backup/backblaze/drive_d/data"


      # 1. Prepare overlay structure

      ENCRYPT_MIDDLE="/storage/backup/backblaze/drive_d/overlay/encrypted"
      # ERROR; Requires to be on the same filesystem as UPPER for atomic file operations!
      OVERLAY_WORK="/storage/backup/backblaze/drive_d/overlay/work"
      OVERLAY_UPPER="/storage/backup/backblaze/drive_d/overlay/upper"

      # NOTE; $VAULT should already be created, would be stupid otherwise. But still attempting to create if not exists to keep the show running
      mkdir -p "$VAULT" "$DRIVE" "$ENCRYPT_MIDDLE" "$OVERLAY_WORK" "$OVERLAY_UPPER"


      # 2. Setup encrypted overlay
      # TODO; Extrapolate init to only work once
      # TODO; Set password
      gocryptfs -reverse -init -plaintextnames "$VAULT"
      # NOTE; Sub-mounts are automatically enabled (disable with -one-file-system)
      gocryptfs -reverse -acl -rw "$VAULT" "$ENCRYPT_MIDDLE"


      # 3. Setup rw-overlay
      mount -t overlay overlay -o lowerdir="$ENCRYPT_MIDDLE",upperdir="$OVERLAY_UPPER",workdir="$OVERLAY_WORK" none "$DRIVE"

      # RESULT: VAULT => [encryption] => ENCRYPT_MIDDLE => [overlayed with r/w directory at OVERLAY_UPPER] => DRIVE
      # Now symlink DRIVE into wine
    '';

    postStop = ''
      DRIVE="/storage/backup/backblaze/drive_d/data"
      ENCRYPT_MIDDLE="/storage/backup/backblaze/drive_d/overlay/encrypted"

      umount "$DRIVE"
    '';

    unitConfig.RequiresMountsFor = [ "/storage/backup/backblaze" ];
    serviceConfig = {
      User = "backblaze";
      #ProtectSystem = "full";
      #ProtectHome = true;
      ReadWritePaths = [ "/storage/backup/backblaze" ];
      BindPaths = [
        # ERROR; Paths mounted as read-only into an overlayfs stay read-only, even though the overlay could make
        # those locations writeable through the upper directory!
        #
        # NOTE; Group directories from the same pool into the same landing directory _on the same pool_
        # Keeping all mounts on the same pool prevents total space fluctuations or miscalculations between
        # filesystem total space and actual counted datasize (last one is mounted in and is larger)
        "/storage/media/immich/originals:/storage/backup/backblaze/drive_d/paths/immich"
        "/storage/postgres/state:/storage/backup/backblaze/drive_d/paths/postgresql"
        "/storage/sqlite/state:/storage/backup/backblaze/drive_d/paths/sqlite"
      ];
    };
  };

  systemd.services."vnc-websockify" = {
    enable = true;
    description = "Service to forward websocket connections to TCP connections (connect to 127.42.88.1:8080)";
    wantedBy = [ config.systemd.targets.backblaze-backup.name ];
    partOf = [ config.systemd.targets.backblaze-backup.name ];
    after = [ config.systemd.services.backblaze-backup.name ];

    path = [ pkgs.python3Packages.websockify ];
    enableStrictShellChecks = true;
    script = "websockify '127.42.88.1:8080' '127.0.0.1:5901'";
  };

  environment.systemPackages = [
    # pkgs.mesa-demos # DEBUG
  ];

  systemd.tmpfiles.settings."backblaze-state" = {
    "/storage"."a+".argument = "group:backblaze:r-X";
    "/storage/backup"."a+".argument = "group:backblaze:r-X";
    "/storage/backup/backblaze"."a+".argument = "group:backblaze:r-X,default:group:backblaze:r-X";

    "/storage/backup/backblaze/drive_d/paths".d = {
      # To bind-mount all backup paths into
      user = "backblaze";
      group = "backblaze";
      mode = "0700";
    };

    "/storage/backup/backblaze/drive_d/overlay".d = {
      # To prepare encryption and overlayfs
      user = "backblaze";
      group = "backblaze";
      mode = "0700";
    };

    "/storage/backup/backblaze/drive_d/data".d = {
      # Actual data presented to wine
      user = "backblaze";
      group = "backblaze";
      mode = "0700";
    };

    "/storage/backup/backblaze/wineprefix".z = {
      user = "backblaze";
      group = "backblaze";
      mode = "0700";
    };
  };

  disko.devices.zpool.storage.datasets = {
    "backup/backblaze" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/backup/backblaze";
      };
    };
    "backup/backblaze/drive_c" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/storage/backup/backblaze/wineprefix";
        refquota = "128GB"; # Consistent statistics of the drive_c
      };
    };
  };

  nixpkgs.overlays = [
    (_final: prev: {
      winetricks = prev.winetricks.overrideAttrs ({
        version = "20250102";
        src = pkgs.fetchFromGitHub {
          owner = "Winetricks";
          repo = "winetricks";
          rev = "e20b2f6f80d175f96208f51800130db7459dd28c"; # == 20250102
          # nix-prefetch-url --unpack https://github.com/Winetricks/winetricks/archive/refs/tags/20250102.zip
          sha256 = "02hdask7wn9vk4i0s43cyzg2xa9aphskbrn8slywsbic6rasyv9a";
        };
      });

      ratpoison = prev.ratpoison.overrideAttrs (old: {
        # Nix by default adds "$out" as prefix to the make script, which is the store path of the derivation.
        # This causes ratpoison to think that directory "/etc" is at "/nix/store/narhash-ratpoison<version/etc", not at
        # the location we expect it to look for configuration files!
        configureFlags = (old.configureFlags or [ ]) ++ [ "--sysconfdir=/etc" ];
      });
    })
  ];
}
