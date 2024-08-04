{ lib, config, pkgs, profiles, ... }: {

  imports = [
    profiles.hypervisor
  ];

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

  networking.hostName = "development";
  networking.domain = "alpha.proesmans.eu";

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "9c522fc1";

  proesmans.filesystem.simple-disk.enable = true;
  proesmans.filesystem.simple-disk.systemd-boot.enable = true;
  proesmans.nix.linux-64 = true;
  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.vscode.enable = true;
  proesmans.vscode.nix-dependencies.enable = true;
  proesmans.home-manager.enable = true;

  # Load Hyper-V kernel modules
  virtualisation.hypervGuest.enable = true;

  # Make me a user!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ "wheel" ]
      ++ lib.optional config.virtualisation.libvirtd.enable
      "libvirtd" # NOTE; en-GB
      ++ lib.optional config.networking.networkmanager.enable
      "networkmanager";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # WARN; Superseded by systemd-ssh-generators!
  # Comes with systemd v256+ and the systemd-ssh-generators feature activated!
  # REF; https://www.freedesktop.org/software/systemd/man/latest/systemd-ssh-proxy.html
  programs.ssh.extraConfig =
    let
      tunnel-script = pkgs.writeShellApplication {
        name = "tunnel-vsock-ssh";
        runtimeInputs = [ pkgs.socat ];
        text = ''
          if [ $# -ne 1 ]; then
            echo "Usage: $0 'vsock/<VM CID>'"
            exit 1
          fi

          # Extract the VM CID from the host argument
          host=$1
          vm_cid=$(echo "$host" | awk -F'/' '{print $2}')

          # Validate CID
          if [ -z "$vm_cid" ]; then
              echo "Error: VM CID is not specified."
              exit 1
          fi

          # Establish socat tunnel!
          socat - VSOCK-CONNECT:"$vm_cid":22
        '';
      };
    in
    ''
      # Usage 'ssh vsock/55', where 55 is the VM Context identifier (CID)
      # VM CID, see option microvm.vsock.cid in the virtual machine configuration
      Host vsock/*
        HostName localhost
        StrictHostKeyChecking no
        UserKnownHostsFile=/dev/null
        ProxyCommand ${lib.getExe tunnel-script} %n
    '';

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

  # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/networking.nix

  # Networking configuration
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;

  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = lib.mkDefault true;

  # The notion of "online" is a broken concept
  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # FIXME: Maybe upstream?
  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
  # followed by a delayed `systemctl start`.
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

  # Hyper-V does not emulate PCI devices, so network adapters remain on their ethX names
  # eth0 receives an address by DHCP and provides the default gateway route
  # eth1 gets a stable link-local address for SSH, because Windows goes fucky wucky with
  # the host bridge network adapter and that's sad because IP's and routes won't stick
  # after a reboot.
  systemd.network.networks = {
    "30-upstream" = {
      # ERROR; Don't forget to enable MAC address spoofing on the VM network interface
      # attached to host adapter "Static Net"!
      # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Applicable if using bridged networking, not if NAT'ing
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "ipv4";
      networkConfig.LinkLocalAddressing = "no";
    };

    "30-hypervisor-connect" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        Address = [ "169.254.245.139/24" "fe80::139/64" ];
        LinkLocalAddressing = "no";
      };
    };
  };

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

  sops = {
    defaultSopsFile = ./secrets.encrypted.yaml;
    # Disable deriving secret decrypters from SSH host keys.
    age.sshKeyPaths = [ ];
    age.keyFile = lib.facts.sops.keypath;
    age.generateKey = false;
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

  sops.secrets.vm-test = {
    sopsFile = ./keys.encrypted.yaml;
    group = "kvm"; # Hardcoded by microvm.nix
    mode = "0440";
    restartUnits = [ "microvm@test.service" ]; # Systemd interpolated service
  };

  microvm.host.enable = lib.mkForce true;
  microvm.vms = {
    test = {
      autostart = true;
      specialArgs = { inherit profiles; };
      config = { pkgs, ... }: {
        networking.hostName = "test";
        imports = [ profiles.micro-vm ];

        sops = {
          defaultSopsFile = ./secrets.encrypted.yaml;
          # Disable deriving secret decrypters from SSH host keys.
          age.sshKeyPaths = [ ];
          age.keyFile = lib.facts.sops.keypath;
          age.generateKey = false;
        };

        microvm.interfaces = [{
          type = "tap";
          id = "tap-test";
          mac = "6a:33:06:88:6c:5b"; # randomly generated
        }];

        microvm.qemu.extraArgs = [
          # DOESN'T WORK
          # "-smbios"
          # "type=11,value=io.systemd.credential:mycredsm=supersecret"
          # DOESN'T WORK
          # "-fw_cfg"
          # "name=opt/io.systemd.credentials/mycredfw,string=supersecret"

          "-fw_cfg"
          "name=opt/secret-seeder/file-1,file=${config.sops.secrets.vm-test.path}"
        ];

        systemd.services.secret-seeder = {
          # WARN; Must copy secrets out of sysfs because the file ergonomy is poor;
          #   - File size of 'raw' is reported as 0
          #   - We're supposed to read the entire contents of 'raw' in one syscall
          description = "Mounts secrets provided from the hypervisor!";
          #requiredBy = [ "local-fs.target" ];
          wantedBy = [ "local-fs.target" ];
          before = [ "local-fs.target" ];
          conflicts = [ "shutdown.target" ];

          unitConfig.DefaultDependencies = "no";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "yes";
            ExecStart =
              let
                copier = pkgs.writers.writePython3Bin "secrets-copier" { } (lib.readFile ./secrets-copier.py);
                script = pkgs.writeShellApplication {
                  name = "invoke-secrets-copier";
                  runtimeInputs = [ copier ];
                  text = ''
                    secrets-copier "file-1" "${lib.facts.sops.keypath}"
                  '';
                };
              in
              lib.getExe script;
          };
        };

        microvm.vsock.cid = 55;
        environment.systemPackages = [
          pkgs.socat
          pkgs.tcpdump
          pkgs.python3
          pkgs.nmap # ncat
        ];

        security.sudo.enable = true;
        security.sudo.wheelNeedsPassword = false;
        users.users.bert-proesmans.extraGroups = [ "wheel" ];
      };
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}
