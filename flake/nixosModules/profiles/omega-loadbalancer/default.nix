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

  nixpkgs.config.permittedInsecurePackages = [
    # NOTE; Need to upgrade to varnish 8.0.1
    # REF; VSV00018: https://vinyl-cache.org/security/VSV00018.html
    "varnish-7.7.3"
  ];
}
