{ pkgs, config, ... }:
{
  networking.domain = "alpha.proesmans.eu";

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  environment.systemPackages = [
    pkgs.curl
    pkgs.socat
    pkgs.tcpdump
    pkgs.python3
    pkgs.nmap # ncat
    pkgs.proesmans.unsock
    pkgs.netcat-openbsd
    pkgs.proesmans.vsock-test
  ];

  system.stateVersion = "24.05";
}
