{
  lib,
  config,
  flake,
  special,
  meta-module,
  ...
}:
{
  sops.secrets = {
    "proxy-vm/ssh_host_ed25519_key" = {
      # New ssh key requires restart of guest
      restartUnits = [ config.systemd.services."microvm@proxy".name ];
    };
  };

  security.acme.certs."alpha.proesmans.eu" = {
    reloadServices = [ config.systemd.services."microvm@proxy".name ];
  };
  systemd.services."microvm@proxy" = {
    # Wait until the certificates exist before starting the guest
    unitConfig.ConditionPathExists = "${
      config.security.acme.certs."alpha.proesmans.eu".directory
    }/fullchain.pem";
  };

  microvm.vms."proxy" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."proxy-vm/ssh_host_ed25519_key".path;
      alpha-certificate-path = config.security.acme.certs."alpha.proesmans.eu".directory;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake special; };

      config =
        { config, special, ... }:
        {
          _file = ./proxy-vm.nix;
          imports = [
            special.profiles.qemu-guest-vm
            (meta-module "proxy")
            ../proxy.nix # VM config
          ];

          config = {
            nixpkgs.hostPlatform = lib.systems.examples.gnu64;
            # ERROR; Number must be unique for each VM!
            # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
            microvm.vsock = {
              #cid = 3000;
              forwarding.enable = true;
              forwarding.cid = 3000;
              forwarding.allowTo = [
                42 # Photos
                300 # SSO
              ];
            };

            proesmans.facts.tags = [ "virtual-machine" ];
            proesmans.facts.meta.parent = parent-hostname;

            microvm.interfaces = [
              {
                type = "macvtap";
                macvtap = {
                  # Private allows the VMs to only talk to the network, no host interaction.
                  # That's OK because we use VSOCK to communicate between host<->guest!
                  mode = "private";
                  link = "main";
                };
                id = "vmac-proxy";
                mac = "52:0d:da:28:b9:5b"; # randomly generated
              }
            ];

            microvm.suitcase.secrets = {
              "ssh_host_ed25519_key".source = guest-ssh-key;
              # Available at "/run/in-secrets-microvm/certificates"
              "certificates".source = alpha-certificate-path;
            };

            services.openssh.hostKeys = [
              {
                path = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
                type = "ed25519";
              }
            ];
            systemd.services.sshd.unitConfig.ConditionPathExists =
              config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
            systemd.services.sshd.serviceConfig.StandardOutput = "journal+console";
          };
        };
    };
}
