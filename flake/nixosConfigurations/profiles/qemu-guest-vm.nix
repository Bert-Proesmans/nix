{ lib, config, ... }:
let
  # A config priority number that is preferred over mkDefault.
  # Useful when multiple options lead to clobbering a singular attribute set, like filesystems being set either
  # manually or through volume definitions etc.
  mkProfileArbitration = lib.mkOverride 900;
in
{
  imports = [
    ./microvm-guest/central-microvm.nix
    ./microvm-guest/suitcase-microvm.nix
    ./microvm-guest/vsock-forwarding-microvm.nix
  ];

  # Generate a nixos module with for each defined vm containing all hypervisor
  # relevant option values.
  microvm.hypervisor = lib.mkForce "qemu";

  microvm.vcpu = lib.mkDefault 1;
  microvm.mem = lib.mkDefault 512; # MB
  # Allow the VM to use an additional 512 MB at boot, reclaimed by the host after settling
  microvm.balloonMem = lib.mkDefault 512;
  microvm.graphics.enable = false;

  # Configure default root filesystem minimizing ram usage.
  # NOTE; All required files for boot and configuration are within the /nix mount!
  # What's left are temporary files, application logs and -artifacts, and to-persist application data.
  #
  # WARN; Custom overide priority so the virtual machine could define volumes to mount at "/"
  fileSystems."/" = mkProfileArbitration {
    device = "rootfs";
    fsType = "tmpfs";
    options = [ "size=100M,mode=0755" ];
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

  microvm.virtiofsd = {
    extraArgs = [
      # Enable proper handling of bindmounts in shared directory!
      "--announce-submounts"
    ];
  };

  networking.useNetworkd = true;

  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [
      "systemd-journal" # Read the systemd service journal without sudo
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
    ];
  };

  # Allow remote management over VSOCK
  services.openssh = {
    enable = true;
    # NOTE; Starting sshd from activation + getting a new login session is slow as frick,
    # expect dropping into a shell to take about 10 seconds on the default microvm resource config.
    startWhenNeeded = true;
    openFirewall = false;
    listenAddresses = lib.mkForce [ ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = "no";
      # Support not compiled in for the settings below
      # (Results in stderr messages)
      # GSSAPIAuthentication = "no";
      # KerberosAuthentication = "no";
    };
  };

  systemd.sockets.sshd = {
    socketConfig = {
      ListenStream = [
        "vsock:${toString config.microvm.vsock.cid}:22"
      ];
    };
  };
}
