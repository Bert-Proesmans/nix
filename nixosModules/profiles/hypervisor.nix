{ lib, pkgs, flake, facts, config, ... }:
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
      my-guests = lib.filterAttrs (_: v: "virtual-machine" == v.type && config.proesmans.facts.host-name == v.parent) facts;
      vsock-match-block = name: v: ''
        Host ${name}
          ProxyCommand ${lib.getExe pkgs.socat} - VSOCK-CONNECT:${toString v.meta.vsock-id}:22
      '';
    in
    lib.pipe my-guests [
      (lib.mapAttrsToList vsock-match-block)
      (lib.concatStringsSep "\n")
    ];
}
