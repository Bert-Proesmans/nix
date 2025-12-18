{ ... }:
{
  imports = [
    ./certificates.nix
    ./memory-handling.nix
    ./monitor.nix
    ./private-network.nix
    ./tls-termination.nix
    ./web-cache.nix
    ./web-security.nix
  ];
}
