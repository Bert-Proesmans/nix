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

  # The hypervisor infrastructure is ran by the systemd framework
  networking.useNetworkd = true;

  boot.kernel.sysctl = {
    # Don't setup the hypervisor to route, but attach MACVTAP interfaces
    # to the physical uplink directly!
    #
    # "net.ipv4.ip_forward" = "1";
    # "net.ipv6.conf.all.forwarding" = "1";
    # "net.ipv6.conf.default.forwarding" = "1";
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
