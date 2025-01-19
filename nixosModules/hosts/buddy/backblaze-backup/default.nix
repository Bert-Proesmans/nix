{ lib, pkgs, config, ... }: {
  # GPU/Graphics configuration
  programs.turbovnc.ensureHeadlessSoftwareOpenGL = true;
  hardware.graphics.enable32Bit = true;

  # Setup virtual display(s) for headless accelerated desktops (for vnc/sunshine)
  # WARN; The amdgpu driver does not support a combination of physical and virtual displays as of writing. The screen will blank after
  # loading the driver module. To see boot logs, do not add the amdgpu driver to initrd with this config!
  # NOTE; But the driver _could_ support this, patches welcomed.
  #
  # lspci;
  # 08:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Raven Ridge [Radeon Vega Series / Radeon Vega Mobile Series] (rev cb)
  boot.extraModprobeConfig = ''
    # PCI ID 08:00.0 == Raven Ridge GPU (APU)
    # Last number is amount of virtual displays to create, in this example one (1)
    options amdgpu virtual_display=0000:08:00.0,1
  '';

  # Enable xserver to mock an environment that turbovnc can take over
  services.xserver.enable = true;
  # Configure openbox session file to be used by turbovnc
  # Use session filename "none+openbox" (none = display manager, openbox = window manager)
  services.xserver.windowManager.openbox.enable = true;

  # DEBUG
  services.displayManager.autoLogin.enable = true;
  # DEBUG
  services.displayManager.autoLogin.user = "bert-proesmans";
  #users.users.test.isNormalUser = true;

  # Disable actually loading the display-manager, so no graphical desktop output on the physical host.
  # DEBUG; X-server session must be initialised for vglrun to work
  # NOTE; NixOS will automatically enable lightDM if no display manager is enabled!
  # services.xserver.autorun = false;

  environment.systemPackages = [
    pkgs.virtualgl
    pkgs.pkgsi686Linux.virtualgl
    pkgs.mesa-demos

    pkgs.proesmans.backblaze-wine-environment
    (
      let
        vnc = pkgs.writeShellApplication {
          name = "vnc-up";
          runtimeInputs = [ pkgs.turbovnc pkgs.python312Packages.websockify ];
          text = ''
            # -vgl argument activates virtualgl rendering and requires virtual gl on path
            vncserver -geometry 1240x900 \
              -securitytypes none \
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
