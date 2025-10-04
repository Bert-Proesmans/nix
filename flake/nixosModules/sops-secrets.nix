{
  lib,
  flake,
  config,
  ...
}:
let
  cfg = config.proesmans.sopsSecrets;
in
{
  # Basic usage of sops-nix, showing the interaction between the encrypted file and nixos configuration.
  # REF; https://github.com/Mic92/sops-nix?tab=readme-ov-file#usage-example
  imports = [ flake.inputs.sops-nix.nixosModules.sops ];

  options.proesmans.sopsSecrets = {
    enable = lib.mkEnableOption "secret management using SOPS-NIX";
    sshHostkeyControl.enable = lib.mkEnableOption "SOPS management of the SSH hostkey";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      ({
        assertions = [
          {
            assertion = builtins.stringLength config.sops.defaultSopsFile > 0;
            message = ''
              Must set a default sops file to retrieve secrets from!
              Set one at 'sops.defaultSopsFile'.
            '';
          }
        ];

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
      })
      (lib.mkIf cfg.sshHostkeyControl.enable {
        sops.secrets.ssh_host_ed25519_key = {
          path = "/etc/ssh/ssh_host_ed25519_key";
          owner = config.users.users.root.name;
          group = config.users.users.root.group;
          mode = "0400";
          restartUnits = lib.optional (
            config.services.openssh.enable && !config.services.openssh.startWhenNeeded
          ) config.systemd.services.sshd.name;
        };

        services.openssh.enable = lib.mkDefault true;
        services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
        services.openssh.hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      })
    ]
  );
}
