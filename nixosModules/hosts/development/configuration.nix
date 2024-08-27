{ lib, config, pkgs, flake-inputs, profiles, ... }: {

  imports = [
    profiles.hypervisor
    ./hardware-configuration.nix
  ];

  networking.hostName = "development";
  networking.domain = "alpha.proesmans.eu";

  proesmans.filesystem.simple-disk.enable = true;
  proesmans.filesystem.simple-disk.systemd-boot.enable = true;
  proesmans.nix.garbage-collect.enable = true;
  # Garbage collect less often, so we don't drop build artifacts from other systems
  proesmans.nix.garbage-collect.development-schedule.enable = true;
  proesmans.nix.registry.fat = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.vscode.enable = true;
  proesmans.vscode.nix-dependencies.enable = true;
  proesmans.home-manager.enable = true;

  sops.defaultSopsFile = ./secrets.encrypted.yaml;
  sops.age.keyFile = "/etc/secrets/decrypter.age";

  # Make me an admin!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Automatically load development shell in project working directories
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  # Pre-install some tools for debugging network/disk/code
  environment.systemPackages = [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.iperf
    pkgs.dig
    pkgs.traceroute
    pkgs.socat
    pkgs.nmap # ncat
  ];

  # Note; default firewall package is IPTables
  networking.firewall.allowedTCPPorts = [
    5201 # Allow incoming IPerf traffic when acting as a server
  ];

  # [upstream] -> eth0 /NAT/ bridge0 -> tap-*
  networking.nat = {
    enable = true;
    # enableIPv6 = true;
    # Upstream interface with internet access. Packets are masquerade'd through here
    externalInterface = "eth0";
    internalInterfaces = [ "bridge0" ];
  };

  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
  };

  sops.secrets.ssh_host_ed25519_key = {
    path = "/etc/ssh/ssh_host_ed25519_key";
    owner = config.users.users.root.name;
    group = config.users.users.root.group;
    mode = "0400";
    restartUnits = [ config.systemd.services.sshd.name ];
  };

  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  sops.secrets."test-vm/ssh_host_ed25519_key" = {
    #group = "kvm"; # Hardcoded by microvm.nix
    #mode = "0440";

    # For virtio ssh
    mode = "0400";
    restartUnits = [ "microvm@test.service" ]; # Systemd interpolated service
  };

  microvm.host.enable = lib.mkForce true;
  microvm.vms =
    let
      host-config = config;
    in
    {
      # test = {
      #   autostart = false;
      #   specialArgs = { inherit flake-inputs; };
      #   config = { lib, ... }: {
      #     imports = [
      #       ../test-vm.nix
      #       ../../profiles/qemu-guest-vm.nix
      #     ];

      #     microvm.vsock.cid = 55;
      #     microvm.interfaces = [{
      #       type = "tap";
      #       id = "tap-test";
      #       mac = "6a:33:06:88:6c:5b"; # randomly generated
      #     }];

      #     microvm.shares = [{
      #       source = "/run/secrets/test-vm";
      #       mountPoint = "/seeds";
      #       tag = "secret-seeds";
      #       proto = "virtiofs";
      #     }];

      #     # microvm.preStart = ''
      #     #   set -e

      #     #   contents="/run/secrets/test-vm"
      #     #   ls -laa "$contents"

      #     #   d=
      #     #   trap '[[ "$d" && -e "$d" ]] && rm -r "$d"' EXIT
      #     #   d=$(mktemp -d)
      #     #   pushd "$d"

      #     #   (set -e; umask 077; ${pkgs.cdrtools}/bin/mkisofs -R -uid 0 -gid 0 -V secret-seeds -o secrets.iso "$contents")
      #     #   popd

      #     #   rm "/var/lib/microvms/test/secrets.iso"
      #     #   ln --force --symbolic "$d/secrets.iso" "/var/lib/microvms/test/secrets.iso"
      #     # '';

      #     microvm.qemu.extraArgs = [
      #       # DOESN'T WORK
      #       # "-smbios"
      #       # "type=11,value=io.systemd.credential:mycredsm=supersecret"
      #       # DOESN'T WORK
      #       # "-fw_cfg"
      #       # "name=opt/io.systemd.credentials/mycredfw,string=supersecret"
      #       # "-fw_cfg"
      #       # "name=opt/secret-seeder/file-1,file=${config.sops.secrets.vm-test.path}"

      #       # "-drive"
      #       # "file=/var/lib/microvms/test/secrets.iso,format=raw,id=secret-seeds,if=none,read-only=on,werror=report"
      #       # "-device"
      #       # "virtio-blk-pci,drive=secret-seeds"
      #     ];

      #     # boot.initrd.availableKernelModules = [ "iso9660" ];

      #     # fileSystems."/seeds" = lib.mkVMOverride {
      #     #   device = "/dev/disk/by-label/secret-seeds";
      #     #   fsType = "iso9660";
      #     #   options = [ "ro" ];
      #     # };

      #     # systemd.services.demo-secret-access = {
      #     #   description = "Demonstrate access to secret";
      #     #   wants = [ "seeds.mount" ];
      #     #   after = [ "seeds.mount" ];
      #     #   wantedBy = [ "multi-user.target" ];
      #     #   script = ''
      #     #     echo "Demo: The secret is: $(cat /seeds/secret)" >&2
      #     #   '';
      #     # };
      #   };
      # };
    };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
