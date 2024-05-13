# This is a lambda. Any -> (Any -> Any)
{ inputs }:
let
  sops-module = inputs.sops-nix.nixosModules.sops;
in
# This is a nixos module. NixOSArgs -> AttrSet
{ ... }:
{
  # Basic usage of sops-nix, showing the interaction between the encrypted file and nixos configuration.
  # REF; https://github.com/Mic92/sops-nix?tab=readme-ov-file#usage-example
  imports = [ sops-module ];

  # Limit age key conversion to the provisioned elliptic curve key.
  # This setting limits warnings during key conversion and decryption.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # NOTE; keys.encrypted.yaml contains sensitive information for deployment purposes. These values cannot be
  # used to install/update a target system.
  # See also; `invoke install` which performs key decryption and nixos deployment.
  #
  # NOTE; secrets.encrypted.yaml contains sensitive information for services. These values must be
  # decipherable by the private SSH hostkey file!

  # TODO
}
