{ lib, pkgs, special, config, ... }:
let
  my-guests = builtins.mapAttrs (_: v: v.config.config) config.microvm.vms;
  ssh-my-guests = builtins.mapAttrs
    (_: v: {
      inherit (v.proesmans.facts.meta) vsock-id;
      forwarding = v.microvm.vsock.forwarding.enable;
    })
    my-guests;
in
{
  imports = [
    special.inputs.microvm.nixosModules.host
    ../microvm-host/central-microvm.nix
    ../microvm-host/suitcase-microvm.nix
    ../microvm-host/vsock-forwarding-microvm.nix
  ];

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

  # ERROR; Secrets disappear when rebuilding the host, mounted folders outside the
  # secrets directory become empty.
  # Tell SOPS-NIX to not cleanup old generations of secrets.
  sops.keepGenerations = 0;

  # Provisions space for microvm volume creation
  # AKA store your newly created volumes at /var/cache/microvm/<name>/<volume>
  systemd.services."microvm@".serviceConfig.CacheDirectory = "microvm/%i";

  # WARN; Superseded by systemd-ssh-generators!
  # Comes with systemd v256+ and the systemd-ssh-generators feature activated!
  # REF; https://www.freedesktop.org/software/systemd/man/latest/systemd-ssh-proxy.html
  programs.ssh.extraConfig =
    let
      vsock-match-block = name: v:
        let
          # ERROR; Must include the interpreter executable because the script directly cannot be "exec'ed".
          proxy-script = pkgs.writers.writePython3 "firecracker-vsock-proxy" { } (builtins.readFile ./firecracker-proxy.py);
        in
        if v.forwarding then ''
          Host ${name}
            ProxyCommand "${pkgs.python3}/bin/python" ${proxy-script} "/run/microvm/vsock/${name}.vsock" 22
        ''
        else ''
          Host ${name}
            ProxyCommand ${lib.getExe pkgs.socat} - VSOCK-CONNECT:${toString v.vsock-id}:22
        '';
    in
    lib.pipe ssh-my-guests [
      (lib.mapAttrsToList vsock-match-block)
      (lib.concatStringsSep "\n")
    ];

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