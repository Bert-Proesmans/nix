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
  ];

  proesmans.vsock-proxy.proxies = [
    {
      # curl to 127.0.0.1:8080
      # -> goes through VSOCK to hypervisor
      # -> http-server listening
      listen.tcp.ip = "127.0.0.1";
      listen.port = 8080;
      transmit.vsock.cid = 2; # hypervisor
      transmit.port = 8080;
    }
  ];

  system.stateVersion = "24.05";
}
