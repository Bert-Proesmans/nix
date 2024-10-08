{ lib, special, ... }: {
  # Basic usage of sops-nix, showing the interaction between the encrypted file and nixos configuration.
  # REF; https://github.com/Mic92/sops-nix?tab=readme-ov-file#usage-example
  imports = [ special.inputs.sops-nix.nixosModules.sops ];

  sops = {
    # ERROR; Each host must set its own secrets file, like below
    # sops.defaultSopsFile = ./secrets.encrypted.yaml;

    # NOTE; Each host could swap out the way it handles secrets
    age.keyFile = lib.mkDefault "/etc/secrets/decrypter.age";

    # NOTE; Each host gets an unique age key that decrypts everything else.
    # The SSH key is also decrypted, instead of being used as the decryption key. This allows rotating
    # both independently.
    gnupg.sshKeyPaths = [ ];
    age.sshKeyPaths = [ ];
    age.generateKey = false;
  };
}
