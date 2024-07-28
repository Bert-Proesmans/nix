# Lambda
{ inputs, commonNixosModules }:
let
  impermanence-module = inputs.impermanence.nixosModules.impermanence;
in
# NixOS Module
{ lib, pkgs, ... }: {
  # Importing the common nixos modules to allow for uniform declarative host configuration between
  # nixos hosts and microVMs.
  imports = commonNixosModules ++ [ impermanence-module ];

  # Generate a nixos module with for each defined vm containing all hypervisor
  # relevant option values.
  microvm.hypervisor = lib.mkForce "qemu";

  microvm.vcpu = lib.mkDefault 1;
  microvm.mem = lib.mkDefault 512;
  # Allow the VM to use an additional 512 MB at boot, reclaimed by the host after settling
  microvm.balloonMem = lib.mkDefault 512;
  microvm.graphics.enable = false;

  # Overwrite default root filesystem minimizing ram usage.
  # NOTE; All required files for boot and configuration are within the /nix mount!
  # What's left are temporary files, application logs and -artifacts, and to-persist application data.
  # TODO; Do I need to configure /tmp ?
  fileSystems."/" = {
    device = "rootfs";
    fsType = "tmpfs";
    options = [ "size=10%,mode=0755" ];
    neededForBoot = true;
  };

  # It is highly recommended to share the host's nix-store
  # with the VMs to prevent building huge images.
  microvm.shares = [{
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "virtiofs";
    # NOTE; Hugetables backed mapping isn't enabled in microvm.nix.
    # - The ZFS compatible kernel has compiled in support
    # - The hugetblfs is not mounted by default
    #   SEEALSO; `nixosModules.profiles.hypervisor`
    # - The qemu VM's are not started making use of hugetables
    #   REF; https://github.com/astro/microvm.nix/blob/ac28e21ac336dbe01b1f1bcab01fd31db3855e40/lib/runners/qemu.nix#L210C20-L210C40
    # ERROR; The parameter below is only used for p9 sharing. This is _not_ the same as virtiofs' accessmode!
    # securityModel = "mapped";
  }];

  networking.useNetworkd = true;
  systemd.network.networks."20-lan" = {
    matchConfig.Type = "ether";
    networkConfig = {
      # All VM's share the same link local address for stable management access
      # from host to VM, for example ssh.
      #
      # USAGE; ssh fe81::1%tap-<vm-name>
      #
      # NOTE; This can be removed after automatic management of local socket for virtual
      # machines is merged into systemd. This socket should provide a backdoor shell into
      # the VM from the host.
      #
      # ERROR; This is currently broken because of weird (unexplored) behaviour of TAP interfaces
      # enslaved in a bridge. In short; the interface doesn't become/act like a port.
      # A "port" is an interface with an IP, which attaches connects the interface to the CPU. The
      # interface is effectively attached to a control plane that should respond to internet control
      # messages (ICMP). This is not happening after assigning an IP to the TAP.
      # Workaround is to have a single VM and connect (ping/ssh) through the bridge0 port.
      Address = [ "fe81::1/64" ];
      DHCP = "yes";
      IPv6AcceptRA = true;
      LinkLocalAddressing = "yes";
    };
  };

  # Required for docker-in-vm
  # systemd.network.networks."19-docker" = {
  #   matchConfig.Name = "veth*";
  #   linkConfig = {
  #     Unmanaged = true;
  #   };
  # };

  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "systemd-journal" # Read the systemd service journal
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;
  # services.openssh.startWhenNeeded = true;
  # systemd.sockets."ssh-vsock" = {
  #   # NOTE; Superseded by Systemd v256+ and available ssh-generator (not immediately packaged in nixos)
  #   # REF; https://github.com/libvirt/libvirt/blob/e62c26a20dced58ea342d9cb8f5e9164dc3bb023/docs/ssh-proxy.rst#L21

  #   wants = [ "ssh-access.target" ];
  #   before = [ "ssh-access.target" ];

  #   socketConfig = {
  #     ListenStream = "vsock::22";
  #     Accept = "yes";
  #     PollLimitIntervalSec = "30s";
  #     PollLimitBurst = "50";
  #     Service = config.systemd.services."sshd@".name;
  #   };
  # };
  systemd.services."ssh-vsock-proxy" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart =
        let
          script = pkgs.writeShellApplication {
            name = "ssh-vsock-proxy";
            runtimeInputs = [ pkgs.socat ];
            text = ''
              socat VSOCK-LISTEN:22,reuseaddr,fork TCP:localhost:22
            '';
          };
        in
        lib.getExe script;
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
