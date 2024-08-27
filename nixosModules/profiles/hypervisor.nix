{ lib, pkgs, flake, config, ... }:
{
  imports = [ flake.inputs.microvm.nixosModules.host ];

  microvm.host.enable = lib.mkDefault false;
  microvm.autostart = [ ];
  # microvm.virtiofsd = {
  #   threadPoolSize = lib.mkDefault 2;
  #   extraArgs = [
  #     "--allow-mmap"
  #     "--cache=never"
  #     "--inode-file-handles=mandatory"
  #   ];
  # };

  # ERROR; Doesn't work because nix thinks the set is open-ended.
  # microvm.vms = builtins.listToAttrs (builtins.map
  #   (name: {
  #     inherit name;
  #     value = {};
  #   })
  #   vm-names);

  # The hypervisor infrastructure is ran by the systemd framework
  networking.useNetworkd = true;

  # Build a bridge!
  systemd.network.netdevs."bridge0" = {
    netdevConfig = {
      Name = "bridge0";
      Kind = "bridge";
    };
  };

  systemd.network.networks."30-link-local-bridge" = {
    matchConfig.Name = "bridge0";
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = true;
    };
    addresses = [
      {
        # Random stable IPv4
        Address = "10.185.165.236/24";
      }
      {
        # Random stable IPv6
        Address = "fd42:d5a4:b5e7::2d7c:b5bb:9ee1:edae/64";
      }
      {
        # Random stable IPv6. Used for connecting to VM's over network
        #
        # REF; https://github.com/astro/microvm.nix/issues/123
        #
        # ERROR; Address is set on the bridge because the TAP won't send neighbour advertisements
        # for its own address. The bridge _does_. So it's either intentional to do something with
        # enslaved TAP, or the bridge config is wrong and filtering out these control packets :/
        Address = "fe81::2d7c:b5bb:9ee1:edae/64";
      }
    ];
    ipv6Prefixes = [{
      # Site-local prefix generated through https://www.unique-local-ipv6.com
      Prefix = "fd42:d5a4:b5e7::/64";
    }];
  };
  # WARN; Allow incoming DHCP requests on the bridge interface
  networking.firewall.interfaces."bridge0".allowedUDPPorts = [ 67 ];

  # Attach all virtual ethernet interfaces to the bridge!
  systemd.network.networks."31-microvm-interfaces" = {
    matchConfig.Name = "vm-* tap-*";
    networkConfig.Bridge = "bridge0";

    #addresses = [{
    # Random stable IPv6. Used for connecting to VM's over network
    #
    # REF; https://github.com/astro/microvm.nix/issues/123
    #
    # ERROR; Doesn't work; the TAP interface becomes unresponsive to any control protocol
    # packets when enslaved in a bridge. Need to set the address on the bridge instead!
    # addressConfig.Address = "fe81::2d7c:b5bb:9ee1:edae/64";
    #}];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = "1";
    "net.ipv6.conf.all.forwarding" = "1";
    "net.ipv6.conf.default.forwarding" = "1";
  };

  # mount /hugetlbfs for virtio/qemu
  # systemd.mounts = [{
  #   where = "/hugetlbfs";
  #   enable = true;
  #   what = "hugetlbfs";
  #   type = "hugetlbfs";
  #   options = "pagesize=2M";
  #   requiredBy = [ "basic.target" ];
  # }];

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
}
