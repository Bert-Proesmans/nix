{ lib, pkgs, config, flake, profiles, meta-module, ... }: {
  sops.secrets = {
    "kanidm-vm/ssh_host_ed25519_key" = {
      mode = "0400"; # Required by sshd
      restartUnits = [
        # New secrets are a new directory (new generation) and bind mount must be updated
        "shared-kanidm-seeds.mount"
        # New ssh key requires restart of guest
        "microvm@kanidm.service"
      ];
    };
    "kanidm-vm/idm_admin_password" = {
      restartUnits = [
        # New secrets are a new directory (new generation) and bind mount must be updated
        "shared-kanidm-seeds.mount"
        # New ssh key requires restart of guest
        "microvm@kanidm.service"
      ];
    };
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

  # Mounted at /shared/immich/<mount-name>
  proesmans.mount-central = {
    defaults.after-units = [ "zfs-mount.service" ];
    directories."kanidm".mounts = {
      "seeds".source = "/run/secrets/kanidm-vm";
      "certs" = {
        source = "/run/certs-kanidm";
        read-only = true;
      };
      "state".source = "/storage/sqlite/state/kanidm";
    };
  };

  systemd.services."microvm-virtiofsd@kanidm".unitConfig = {
    # Run the microvms after certificates are acquired!
    requires = [ "acme-finished-idm.proesmans.eu.target" ];
    after = [ "acme-finished-idm.proesmans.eu.target" ];
    RequiresMountsFor = config.proesmans.mount-central.directories."kanidm".bind-paths;
  };

  security.acme.certs."idm.proesmans.eu" = {
    # NOTE; Currently no mechanism to reload services inside the vm directly.
    #
    # ERROR; Must reload/restart the virtual machine, because reloading the virtiofs daemon
    # with a connected machine will fail reloading and do nothing (as far as I understand).
    reloadServices = [ "microvm@kanidm.service" ];
    postRun = ''
      destination="/run/certs-kanidm"
      FIND="${pkgs.findutils}/bin/find"
      CP="${pkgs.coreutils}/bin/cp"
      RM="${pkgs.coreutils}/bin/rm"

      # First cleanup the destination directory
      $FIND "$destination"/ -maxdepth 1 -type f -exec $RM --force {} \;

      # The certificate directory gets removed during renewal.
      # We're bind mounting the certificates into a virtiofs share.
      # We need the files in a stable folder, because removing the source directory of a bind mount
      # gives issues.
      $FIND "." -maxdepth 1 -type f -exec $CP {} "$destination"/ \;
    '';
  };

  systemd.tmpfiles.settings = {
    "10-certs-copy" = {
      # NOTE; /run is a RAMFS, it needs to be re-provisioned at every boot!
      # This rule copies all contents from cert directory to the /run directory
      "/run/certs-kanidm".C.argument = config.security.acme.certs."idm.proesmans.eu".directory;

      # Adjust permissions on /run directory and all contents
      "/run/certs-kanidm".Z = {
        user = "root";
        group = "root";
        mode = "0700";
      };
    };
  };

  microvm.vms."kanidm" =
    let
      parent-hostname = config.networking.hostName;
    in
    {
      autostart = true;
      specialArgs = { inherit lib flake profiles; };

      # The configuration for the MicroVM.
      # Multiple definitions will be merged as expected.
      config = { config, profiles, ... }: {
        _file = ./kanidm-vm.nix;

        imports = [
          profiles.qemu-guest-vm
          (meta-module "SSO")
          ../SSO/configuration.nix # VM config
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

          microvm.shares = [
            {
              source = "/shared/kanidm";
              mountPoint = "/data";
              tag = "state-kanidm";
              proto = "virtiofs";
            }
          ];
        };
      };
    };
}
