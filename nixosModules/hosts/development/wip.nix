{ lib, flake, special, meta-module, pkgs, config, ... }:
{
  services.xserver.enable = true;
  services.xserver.windowManager.ratpoison = {
    enable = true;
  };

  environment.systemPackages = [
    # support both 32- and 64-bit applications
    pkgs.wineWowPackages.stableFull

    # winetricks (all versions)
    (pkgs.winetricks.overrideAttrs (_final: _previous: {
      version = "20250102";
      src = pkgs.fetchFromGitHub {
        owner = "Winetricks";
        repo = "winetricks";
        rev = "e20b2f6f80d175f96208f51800130db7459dd28c"; # == 20250102
        # nix-prefetch-url --unpack https://github.com/Winetricks/winetricks/archive/refs/tags/20250102.zip
        sha256 = "02hdask7wn9vk4i0s43cyzg2xa9aphskbrn8slywsbic6rasyv9a";
      };
    }))

    pkgs.turbovnc
    pkgs.virtualgl
    pkgs.mesa-demos
    pkgs.ratpoison

    pkgs.python312Packages.websockify
    pkgs.openssl

    (pkgs.writeShellApplication {
      name = "setup-wine-test";
      runtimeInputs = [ pkgs.wineWowPackages.stableFull ];
      text =
        let
          winInstallerNuget = pkgs.fetchzip {
            url = "https://www.nuget.org/api/v2/package/WixToolset.Dtf.WindowsInstaller/5.0.2";
            stripRoot = false;
            extension = "zip";
            # nix-prefetch-url --unpack <URL>
            # Defaults to outputting sha256 hash.
            # Note that the installer is not version pinned! Only when the hash is manually changed a redownload will occur
            # (or a nix garbage collect has run)
            sha256 = "17xk799yzykk2wjifnwk2dppjkrwb8q6c70gsf7rl8rw7q7l1z5v";
          };
          powershellWindows = pkgs.fetchurl {
            url = "https://github.com/PowerShell/PowerShell/releases/download/v7.2.21/PowerShell-7.2.21-win-x64.msi";
            sha256 = "1ba65dn1dzb7ihkdllhbh876zckl3n5yca92i73nxml93jql0xj0";
          };
        in
        ''
          export WINEPREFIX="$HOME/.wine"
          rm -rf "$WINEPREFIX"
          wineboot --init

          cp ${winInstallerNuget}/lib/net20/WixToolset.Dtf.WindowsInstaller.dll "$WINEPREFIX"/drive_c/WixToolset.Dtf.WindowsInstaller.dll
          wine msiexec /quiet /i ${powershellWindows} ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1
        '';
    })
  ];

  microvm.vms.test =
    let
      parent-hostname = config.networking.hostName;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake special; };
      config = { lib, pkgs, config, ... }: {
        _file = ./test-vm.nix;

        imports = [
          special.profiles.qemu-guest-vm
          (meta-module "test")
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          microvm.mem = 4096;
          microvm.vsock.cid = 666;
          system.stateVersion = "24.11";

          proesmans.facts.tags = [ "virtual-machine" ];
          proesmans.facts.meta.parent = parent-hostname;

          microvm.volumes = [{
            # Persist tmp directory because of big downloads, video processing, and chunked uploads
            autoCreate = true;
            image = "/var/cache/microvm/test/root.img";
            label = "root-test";
            # NOTE; Sticky bit is automatically set
            mountPoint = "/";
            size = 5 * 1024; # Megabytes
            fsType = "ext4";
          }];

          microvm.interfaces = [{
            type = "tap"; # tap for easier host<>guest communication
            macvtap = {
              # Private allows the VMs to only talk to the network, no host interaction.
              # That's OK because we use VSOCK to communicate between host<->guest!
              mode = "private";
              link = "main";
            };
            id = "vmac-test";
            mac = "6e:7b:3b:fd:9a:b3"; # randomly generated
          }];

          networking.firewall.allowedUDPPorts = [ 5900 5901 8080 ];
          networking.firewall.allowedTCPPorts = [ 5900 5901 8080 ];


          # Not using sunshine, which might actually be easier all in all to setup 🤔
          environment.systemPackages = [
            # support both 32- and 64-bit applications
            # TODO; Might want to override the package, using overlay, to make more packages available inside the closure
            # REF; https://github.com/NixOS/nixpkgs/blob/121560b0d0464b191411d8003232e07c7722612f/pkgs/applications/emulators/wine/default.nix#L45
            pkgs.wineWowPackages.stable

            # winetricks (all versions)
            pkgs.winetricks

            pkgs.turbovnc
            pkgs.virtualgl
            pkgs.mesa-demos
            pkgs.ratpoison

            pkgs.python312Packages.websockify
            pkgs.openssl
            (pkgs.writeShellApplication {
              name = "vnc-up";
              runtimeInputs = [ pkgs.turbovnc pkgs.python312Packages.websockify pkgs.openssl pkgs.virtualgl ];
              text = ''
                export XSESSIONSDIR="${config.services.displayManager.sessionData.desktops}/share/xsessions"

                openssl req -new -x509 -days 365 -nodes -out ~/self.pem -keyout ~/self.pem
                # Omitted -vgl argument
                vncserver -geometry 1240x900 \
                  -securitytypes none \
                  -xstartup ${pkgs.writeScript "xstartup.turbovnc" (builtins.readFile ./xstartup.turbovnc)} \
                  -wm 'none+ratpoison'
                websockify --daemon --web=${pkgs.novnc}/share/webapps/novnc --cert=~/self.pem '[::]:8080' 'localhost:5901'
              '';
            })
          ];

          # Make sure software finds the software renderer from turbovnc
          programs.turbovnc.ensureHeadlessSoftwareOpenGL = true;
          hardware.graphics.enable32Bit = true;

          # Easiest way to get dependencies and configuration generated for us, but we want to disable launch of graphical target
          services.xserver.enable = true;
          systemd.services.display-manager.enable = lib.mkForce false;
          # Constructs session file "none+ratpoison" (none = desktopmanager, ratpoison is windowmanager)
          services.xserver.windowManager.ratpoison.enable = true;

          environment.etc."ratpoisonrc".text = ''
            set border 1
            exec ${lib.getExe (pkgs.writeShellApplication {
              name = "launch-wine";
              runtimeInputs = [pkgs.wineWowPackages.stable pkgs.winetricks];
              text = ''
                # PREFIX/dosdevices are the volumes (drives) used by wine, conventionally symlinks
                # PREFIX/drive_c is the location where C: drive contents are stored, every windows machine
                # has at least a C: drive
                #
                # PREFIX/drive_{d..z} could create these folders or mount other filesystems, but that's not
                # actually required
                # 'PREFIX/dosdevices/{d..z}:' create symlinks here to other filesystems so the wine server can
                # provide their data as volume to the programs
                #
                WINEPREFIX="''$(pwd)/wine" # container for all wine related software and configuration
                export WINEPREFIX

                WINEARCH="win64" # Force a 64-bit windows environment always
                export WINEARCH

                WINEDLLOVERRIDES="mscoree=" # Disable Mono installation
                export WINEDLLOVERRIDES

                log_file="''${STARTUP_LOGFILE:-''${WINEPREFIX}/dosdevices/c:/backblaze-wine-startapp.log}"

                log_message() {
                    echo "$(date): $1" >> "$log_file"
                }

                # Pre-initialize Wine
                if [ ! -f "''${WINEPREFIX}/system.reg" ]; then
                    echo "WINE: Wine not initialized, initializing"
                    wineboot -i
                    cd "''${WINEPREFIX}/drive_c/windows/Fonts" && \
                      find ${pkgs.wineWowPackages.fonts}/share/fonts/wine -type f -name '*.ttf' -exec ln --symbolic "{}" . \;
                    log_message "WINE: Initialization done"
                fi

                # DEMO; Open control panel
                wine64 control
                log_message "WINE: DONE"
              '';
            })}
          '';

          # services.networking.websockify.enable = true;
          # services.networking.websockify.portMap."80" = 5901;
        };
      };
    };
}
