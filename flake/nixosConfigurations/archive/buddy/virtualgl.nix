# Setup a secure bridge between virtualgl wrapped surfaces and the x-display attached to the graphics hardware
{ lib, pkgs, ... }:
{
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

  # WARN; Changing ownership of /dev/dri/* devices breaks convention of being part of the group "video".
  services.udev.extraRules = ''
    KERNEL=="card*|renderD*", MODE="0660", OWNER="root", GROUP="vglusers"
  '';

  environment.systemPackages = [
    pkgs.virtualgl
    pkgs.pkgsi686Linux.virtualgl
  ];

  systemd.tmpfiles.rules = [
    "d /etc/opt/VirtualGL 0750 lightdm vglusers -"
  ];

  # _Only_ users in the "vglusers" group are allowed to perform rendering by executing vglrun !
  users.groups.vglusers = { };

  services.xserver = {
    enable = true;
    autorun = true;
    extraConfig = ''
      Section "Extensions"
        Option "XTEST" "Disable" # Recommended by virtualGL developers
      EndSection

      # NOTE; No Direct Rendering Infrastructure (DRI) config configured; `vglrun glxinfo | grep rendering` reports direct rendering enabled.
      # Also /dev/dri/* devices are populated.
      Section "DRI"
        Group "vglusers"         # Recommended by virtualGL developers
        Mode 0660
      EndSection
    '';
    displayManager.lightdm = {
      enable = true;
      extraSeatDefaults = ''
        allow-guest=false
        greeter-hide-users=true
        greeter-setup-script=${lib.getExe' pkgs.virtualgl "vglgenkey"}
      '';
    };
  };

  nixpkgs.overlays = [
    (final: prev: {
      virtualgl = prev.virtualgl.overrideAttrs (old: {
        # TODO; Should upstream this wrapper and create a nice nixos module around it
        #
        # vglrun and vglgenkey lack PATH for referenced binaries
        # vglrun is wrapped with runtime libraries for both virtualgl-64bit and virtualgl-32bit.
        #
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];

        # WARN; when buildCommand is set, the phases will _not run_!
        # REF; https://nixos.org/manual/nixpkgs/stable/#sec-stdenv-phases @paragraph-2
        buildCommand = old.buildCommand + ''
          wrapProgram $out/bin/vglrun \
            --prefix PATH : "${
              lib.makeBinPath [
                final.coreutils
                final.nettools
                final.gnused
              ]
            }"

          wrapProgram $out/bin/vglgenkey \
            --prefix PATH : "${
              lib.makeBinPath [
                final.xorg.xauth
                final.gawk
              ]
            }"
        '';
      });
    })
  ];
}
