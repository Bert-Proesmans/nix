{ lib, pkgs, config, ... }: {
  # GPU/Graphics configuration
  programs.turbovnc.ensureHeadlessSoftwareOpenGL = true;
  hardware.graphics.enable32Bit = true;

  # Configure openbox session file to be used by turbovnc
  # Use session filename "none+openbox" (none = desktop manager, openbox = window manager)
  services.xserver.windowManager.openbox.enable = true;

  environment.systemPackages = [
    pkgs.mesa-demos

    pkgs.proesmans.backblaze-wine-environment
    (
      let
        vnc = pkgs.writeShellApplication {
          name = "vnc-up";
          runtimeInputs = [ pkgs.turbovnc pkgs.python312Packages.websockify pkgs.virtualgl ];
          text = ''
            # -vgl argument activates virtualgl rendering and requires virtual gl on path
            vncserver -geometry 1240x900 \
              -securitytypes none \
              -vgl \
              -xstartup ${pkgs.writeShellScript "xstartup.turbovnc" (builtins.readFile ./xstartup.turbovnc)} \
              -wm 'none+openbox'
            websockify '127.42.88.1:8080' 'localhost:5901'
          '';
        };
      in
      pkgs.symlinkJoin {
        name = "vnc-up";
        paths = [ vnc ];
        nativeBuildInputs = [ pkgs.makeWrapper ];

        postBuild = ''
          wrapProgram $out/bin/vnc-up \
            --set XSESSIONSDIR "${config.services.displayManager.sessionData.desktops}/share/xsessions" \
            --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib/:/run/opengl-driver-32/lib:${lib.makeLibraryPath [pkgs.virtualglLib pkgs.pkgsi686Linux.virtualglLib]}"
        '';
      }
    )
    (pkgs.symlinkJoin {
      name = "xvglrun";
      paths = [ pkgs.virtualgl ];
      nativeBuildInputs = [ pkgs.makeWrapper ];

      postBuild = ''
        wrapProgram "$out/bin/vglrun" \
          --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib/:/run/opengl-driver-32/lib:${lib.makeLibraryPath [pkgs.virtualglLib pkgs.pkgsi686Linux.virtualglLib]}"

        mv "$out/bin/vglrun" "$out/bin/xvglrun"
      '';
    })
  ];
}
