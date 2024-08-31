{ lib, pkgs, flake, facts, config, ... }:
let
  my-guests = builtins.mapAttrs (_: v: v.config.config) config.microvm.vms;
  ssh-my-guests = builtins.mapAttrs (_: v: { vsock-id = v.microvm.vsock.cid; }) my-guests;
in
{
  imports = [ flake.inputs.microvm.nixosModules.host ];

  # The hypervisor infrastructure is ran by the systemd framework
  networking.useNetworkd = true;
  microvm.host.enable = lib.mkDefault false;
  microvm.autostart = [ ];
  microvm.virtiofsd = {
    extraArgs = [
      # Enable proper handling of bindmounts in shared directory!
      "--announce-submounts"
    ];
  };

  # WARN; Superseded by systemd-ssh-generators!
  # Comes with systemd v256+ and the systemd-ssh-generators feature activated!
  # REF; https://www.freedesktop.org/software/systemd/man/latest/systemd-ssh-proxy.html
  programs.ssh.extraConfig =
    let
      vsock-match-block = name: v: ''
        Host ${name}
          ProxyCommand ${lib.getExe pkgs.socat} - VSOCK-CONNECT:${toString v.vsock-id}:22
      '';
    in
    lib.pipe ssh-my-guests [
      (lib.mapAttrsToList vsock-match-block)
      (lib.concatStringsSep "\n")
    ];

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
}
