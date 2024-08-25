{ lib, pkgs, flake-inputs, config, ... }: {
  # Basic usage of sops-nix, showing the interaction between the encrypted file and nixos configuration.
  # REF; https://github.com/Mic92/sops-nix?tab=readme-ov-file#usage-example
  imports = [ flake-inputs.sops-nix.nixosModules.sops ];

  config = {
    # Prevent replacing the running kernel w/o reboot
    security.protectKernelImage = true;

    sops = {
      # ERROR; Each host must set its own secrets file, like below
      # sops.defaultSopsFile = ./secrets.encrypted.yaml;

      # NOTE; Each host gets an unique age key that decrypts everything else.
      # The SSH key is also decrypted, instead of being used as the decryption key. This allows rotating
      # both independently.
      gnupg.sshKeyPaths = [ ];
      age.sshKeyPaths = [ ];
      age.keyFile = "/etc/secrets/decrypter.age";
      age.generateKey = false;
    };

    users.users.bert-proesmans = {
      isNormalUser = true;
      description = "Bert Proesmans";
      extraGroups = [ ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
      ];
    };
  };
}
