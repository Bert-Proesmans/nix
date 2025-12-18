{ ... }:
{
  imports = [
    ./initrd-network.nix
    ./initrd-ssh.nix
    ./users.nix
  ];
}
