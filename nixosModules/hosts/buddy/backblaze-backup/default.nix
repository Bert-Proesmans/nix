{ lib, pkgs, config, ... }:
let
  xstartup = pkgs.writeShellApplication {
    name = "xstartup.turbovnc";
    runtimeInputs = [ pkgs.gnugrep pkgs.gnused pkgs.virtualgl ];
    text = builtins.readFile ./xstartup-turbovnc.sh;
  };

  backblaze-wine-environment = pkgs.proesmans.backblaze-wine-environment.override ({
    # Add these packages to the share library path
    libraries = [
      pkgs.freetype # FreeType for Wine
      pkgs.virtualglLib # VirtualGL libs (vglrun)
      pkgs.pkgsi686Linux.virtualglLib # 32-bit VirtualGL libs (vglrun)
    ];
  });

  # ERROR; vglrun FLIPPIN RESETS LD_LIBRARY_PATH!
  # Manually configure the vgl invocation with proper arguments using TVNC_VGLRUN.
  #
  # +vm : enables window manager compatibility
  # -ld : prefix this string before the reset LD_LIBRARY_PATH
  #   - need freetype for wine
  #   - add environment library path for opengl drivers (and other important stuff)
  #NEWLLDP=(vglrun +vm -ld "${}:${config.environment.variables.LD_LIBRARY_PATH or ""}")
  #TVNC_VGLRUN="''${NEWLLDP[*]}"; export TVNC_VGLRUN

  _vnc = pkgs.writeShellApplication {
    name = "vnc-up";
    runtimeInputs = [ pkgs.turbovnc pkgs.python312Packages.websockify pkgs.virtualgl ];
    text = ''
      # -vgl argument activates virtualgl rendering and requires virtual gl on path
      # -localhost restricts accepted connections
      # -nevershared + -disconnect force only one active connection into the session
      # -nointerframe disables calculating interframe distances saving cpu and increasing bandwidth usage when software performs runaway draws
      vncserver :1 \
        -fg \
        -autokill \
        -geometry 1240x900 \
        -securitytypes none -localhost \
        -xstartup ${lib.getExe xstartup} \
        -wm 'none+ratpoison' \
        -depth 24 \
        -nointerframe

    '';
  };
  vnc-up = pkgs.symlinkJoin {
    name = "vnc-up";
    paths = [ _vnc ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      # freetype libraries added for wine to stop whineing huehehe
      # VGL_FPS limits the amount of rendered frames
      wrapProgram $out/bin/vnc-up \
        --set-default XSESSIONSDIR "${config.services.displayManager.sessionData.desktops}/share/xsessions" \
        --set-default VGL_FPS 20 \
        --set-default DISABLE_VIRTUAL_DESKTOP true
    '';
  };
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
    #exec ${lib.getExe backblaze-wine-environment}
    #echo WINE environment started
    # quit
  '';

  users.users.backblaze = {
    # Normal user for opening shell and assuming identity
    isNormalUser = true;
    group = "backblaze";
    extraGroups = [ "vglusers" ];
    home = "/storage/backup/backblaze";
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
    after = [ "systemd-tmpfiles-setup.service" config.systemd.services.display-manager.name ];
    restartTriggers = [ (config.environment.etc."ratpoisonrc".source or null) ];

    script = lib.getExe' vnc-up "vnc-up";
    serviceConfig.User = "backblaze";
    serviceConfig.ReadWritePaths = [ "/storage/backup/backblaze" ];
    unitConfig.RequiresMountsFor = [ "/storage/backup/backblaze" ];
    environment.WINEPREFIX = "/storage/backup/backblaze/wineprefix";
  };

  systemd.services."vnc-websockify" = {
    enable = true;
    description = "Service to forward websocket connections to TCP connections (connect to 127.42.88.1:8080)";
    wantedBy = [ config.systemd.targets.backblaze-backup.name ];
    partOf = [ config.systemd.targets.backblaze-backup.name ];
    after = [ config.systemd.services.backblaze-backup.name ];

    script = ''
      ${pkgs.python3Packages.websockify}/bin/websockify '127.42.88.1:8080' '127.0.0.1:5901'
    '';
  };

  environment.systemPackages = [
    pkgs.mesa-demos # DEBUG
    backblaze-wine-environment # DEBUG - run-backblaze-wine-environment
    vnc-up
  ];

  systemd.tmpfiles.settings."backblaze-state" = {
    "/storage"."a+".argument = "group:backblaze:r-X";
    "/storage/backup"."a+".argument = "group:backblaze:r-X";

    "/storage/backup/backblaze".d = {
      user = "backblaze";
      group = "backblaze";
      mode = "0700";
    };

    "/storage/backup/backblaze/wineprefix".d = {
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
