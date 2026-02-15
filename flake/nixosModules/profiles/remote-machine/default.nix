{ lib, ... }:
{
  imports = [
    ./initrd-network.nix
    ./initrd-ssh.nix
    ./users.nix
  ];

  programs.ssh.systemd-ssh-proxy.enable = lib.mkDefault false;
  systemd.generators.systemd-ssh-generator = lib.mkDefault "/dev/null";
  systemd.sockets.sshd-unix-local.enable = lib.mkDefault false;
  systemd.sockets.sshd-vsock.enable = lib.mkDefault false;
}
