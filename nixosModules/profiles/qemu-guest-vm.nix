{ lib, pkgs, ... }: {
  imports = [
    # flake.inputs.impermanence.nixosModules.impermanence
  ];

  # Generate a nixos module with for each defined vm containing all hypervisor
  # relevant option values.
  microvm.hypervisor = lib.mkForce "qemu";

  microvm.vcpu = lib.mkDefault 1;
  microvm.mem = lib.mkDefault 512;
  # Allow the VM to use an additional 512 MB at boot, reclaimed by the host after settling
  microvm.balloonMem = lib.mkDefault 512;
  microvm.graphics.enable = false;

  # Configure default root filesystem minimizing ram usage.
  # NOTE; All required files for boot and configuration are within the /nix mount!
  # What's left are temporary files, application logs and -artifacts, and to-persist application data.
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
    #
    # ERROR; The parameter below is only used for p9 sharing. This is _not_ the same as virtiofs' accessmode!
    # securityModel = "mapped";
  }];

  networking.useNetworkd = true;

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

  # Allow remote management over VSOCK
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = "no";
      GSSAPIAuthentication = "no";
      KerberosAuthentication = "no";
    };
    openFirewall = false;
    listenAddresses = [{
      addr = "127.0.0.1";
      port = 22;
    }];
  };

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
}
