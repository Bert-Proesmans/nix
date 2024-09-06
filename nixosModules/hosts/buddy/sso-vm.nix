{ lib, pkgs, config, flake, profiles, meta-module, ... }: {
  sops.secrets = {
    "sso-vm/ssh_host_ed25519_key" = {
      # New ssh key requires restart of guest
      restartUnits = [ config.systemd.services."microvm@sso".name ];
    };
    "idm/idm_admin_password" = { };
    "idm/openid-secret-immich" = { };
  };

  # Kanidm state is basically an SQLite database. This dataset is tuned for that use case.
  disko.devices.zpool.storage.datasets."sqlite/state/kanidm" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/storage/sqlite/state/kanidm";
      acltype = "posixacl"; # Required by virtiofsd
      xattr = "sa"; # Required by virtiofsd
    };
  };

  security.acme.certs."idm.proesmans.eu" = {
    reloadServices = [ config.systemd.services."microvm@sso".name ];
  };
  systemd.services."microvm@sso" = {
    # Wait until the certificates exist before starting the guest
    unitConfig.ConditionPathExists = "${config.security.acme.certs."idm.proesmans.eu".directory}/fullchain.pem";
  };

  microvm.vms."sso" =
    let
      parent-hostname = config.networking.hostName;
      guest-ssh-key = config.sops.secrets."sso-vm/ssh_host_ed25519_key".path;
      idm-certificate-path = config.security.acme.certs."idm.proesmans.eu".directory;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake profiles; };

      # The configuration for the MicroVM.
      # Multiple definitions will be merged as expected.
      config = { config, profiles, ... }: {
        _file = ./sso-vm.nix;

        imports = [
          profiles.qemu-guest-vm
          (meta-module "sso")
          ../sso/configuration.nix # VM config
        ];

        config = {
          nixpkgs.hostPlatform = lib.systems.examples.gnu64;
          # ERROR; Number must be unique for each VM!
          # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
          microvm.vsock.cid = 300;

          proesmans.facts.tags = [ "virtual-machine" ];
          proesmans.facts.meta.parent = parent-hostname;

          microvm.interfaces = [{
            type = "macvtap";
            macvtap = {
              # Private allows the VMs to only talk to the network, no host interaction.
              # That's OK because we use VSOCK to communicate between host<->guest!
              mode = "private";
              link = "main";
            };
            id = "vmac-kanidm";
            mac = "9e:30:e8:e8:b1:d0"; # randomly generated
          }];

          microvm.central.shares = [
            ({
              source = "/run/secrets/idm";
              mountPoint = "/seeds";
              tag = "passwords-kanidm";
            })
            ({
              source = "/storage/sqlite/state/kanidm";
              mountPoint = "/var/lib/kanidm";
              tag = "state-kanidm";
            })
          ];

          microvm.suitcase.secrets = {
            "ssh_host_ed25519_key".source = guest-ssh-key;
            # Available at "/run/in-secrets-microvm/certificates"
            "certificates".source = idm-certificate-path;
          };

          services.openssh.hostKeys = [
            {
              path = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
              type = "ed25519";
            }
          ];
          systemd.services.sshd.unitConfig.ConditionPathExists = config.microvm.suitcase.secrets."ssh_host_ed25519_key".path;
          systemd.services.sshd.serviceConfig.StandardOutput = "journal+console";
        };
      };
    };
}
