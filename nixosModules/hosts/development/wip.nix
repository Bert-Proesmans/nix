{ lib, flake, special, meta-module, pkgs, config, ... }:
let

in
{
  services.xserver.enable = true;
  services.xserver.windowManager.ratpoison = {
    enable = true;
  };

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
          microvm.vsock.cid = 666;
          system.stateVersion = "24.11";

          proesmans.facts.tags = [ "virtual-machine" ];
          proesmans.facts.meta.parent = parent-hostname;

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


          environment.systemPackages = [
            # support both 32- and 64-bit applications
            pkgs.wineWowPackages.stable

            # winetricks (all versions)
            pkgs.winetricks

            pkgs.turbovnc
            pkgs.virtualgl
            pkgs.ratpoison

            pkgs.python312Packages.websockify
            pkgs.openssl
            (pkgs.writeShellApplication {
              name = "vnc-up";
              runtimeInputs = [ pkgs.turbovnc pkgs.python312Packages.websockify pkgs.openssl pkgs.virtualgl ];
              text = ''
                export XSESSIONSDIR="${config.services.displayManager.sessionData.desktops}/share/xsessions"

                openssl req -new -x509 -days 365 -nodes -out ~/self.pem -keyout ~/self.pem
                vncserver -geometry 1240x900 -vgl \
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
            exec ${lib.getExe pkgs.writeShellApplication {
              name = "launch-wine";
              runtimeInputs = [pkgs.wineWowPackages.stable pkgs.winetricks];
              text = ''
                log_file="''${STARTUP_LOGFILE:-''${WINEPREFIX}dosdevices/c:/backblaze-wine-startapp.log}"

                log_message() {
                    echo "$(date): $1" >> "$log_file"
                }

                # Pre-initialize Wine
                if [ ! -f "''${WINEPREFIX}system.reg" ]; then
                    echo "WINE: Wine not initialized, initializing"
                    wineboot -i
                    log_message "WINE: Initialization done"
                fi

                cd "''$WINEPREFIX"
                winetricks vd=off

                # <TODO>
              '';
            }}
          '';

          # services.networking.websockify.enable = true;
          # services.networking.websockify.portMap."80" = 5901;
        };
      };
    };
}
