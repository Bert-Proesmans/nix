{ lib, pkgs, config, flake, profiles, home-configurations, meta-module, ... }: {
  sops.secrets."kanidm-vm/ssh_host_ed25519_key" = {
    mode = "0400";
  };
  sops.secrets."kanidm-vm/idm_admin_password" = { };

  # Kanidm state is basically an SQLite database. This dataset is tuned for that use case.
  disko.devices.zpool.zstorage.datasets."vm/kanidm" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/vm/kanidm"; # Default, but good to be explicit
      logbias = "latency";
      recordsize = "64K";
    };
  };

  security.acme.certs."idm.proesmans.eu" = {
    # TODO
    # NOTE; Currently no mechanism to reload services inside the vm directly.
    reloadServices = [ "microvm-virtiofsd@kanidm.service" ];
  };

  systemd.targets."microvms" = {
    # Run the microvms after certificates are acquired!
    wants = [ "acme-finished-idm.proesmans.eu.target" ];
    after = [ "acme-finished-idm.proesmans.eu.target" ];
  };

  # Squash permissions of the acme certificates to root by _simply copying the files_
  # It's possible to do this with bind mounting and 1:1 ID-mapping before going 
  # through virtiofs, but unwieldly.
  # REF; https://gitlab.com/virtio-fs/virtiofsd/-/issues/152#note_2005451839
  #
  #
  # OR Not required anymore when virtiofsd gets updated with internal UID/GID mapping (host-side)!
  # REF; https://gitlab.com/virtio-fs/virtiofsd/-/merge_requests/237
  # OR Not required anymore when virtiofsd gets updated for mount UID/GID mapping (vm-side)!
  # REF; https://gitlab.com/virtio-fs/virtiofsd/-/merge_requests/245
  #
  # WARN; Assumes the service runs as root!
  assertions = [
    {
      assertion = config.systemd.services."microvm-virtiofsd@".serviceConfig?User -> config.systemd.services."microvm-virtiofsd@".serviceConfig.User == "root";
      message = ''
        The virtiofs service must run as root user, or change the approach to certificate pemission squashing!
      '';
    }
  ];
  systemd.services."microvm-virtiofsd@kanidm" = {
    serviceConfig.RuntimeDirectory = [ "kanidm" "kanidm/certs" ];
    serviceConfig.ExecStartPre =
      let
        script = pkgs.writeShellApplication {
          name = "copy-certs-kanidm";
          runtimeInputs = [ pkgs.util-linux ];
          text = ''
            certdir="/var/lib/acme/idm.proesmans.eu"
            destination="/run/kanidm/certs"

            find "$certdir" -maxdepth 1 -type f -exec cp {} "$destination"/ \;
          '';
        };
      in
      lib.getExe script;
  };

  microvm.vms.kanidm = {
    autostart = true;
    specialArgs = { inherit lib flake profiles; };

    # The configuration for the MicroVM.
    # Multiple definitions will be merged as expected.
    config = { lib, config, profiles, ... }: {
      _file = ./kanidm-vm.nix;

      imports = [
        profiles.qemu-guest-vm
        (meta-module "SSO")
        ../SSO/configuration.nix # VM config
      ];

      config = {
        # ERROR; Number must be unique for each VM!
        # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
        microvm.vsock.cid = 300;

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
            source = "/run/secrets/kanidm-vm";
            mountPoint = "/seeds";
            tag = "secrets-kanidm";
            proto = "virtiofs";
          }
          {
            source = "/vm/kanidm";
            mountPoint = "/data/state";
            tag = "state-kanidm";
            proto = "virtiofs";
          }
          {
            source = "/run/kanidm/certs";
            mountPoint = "/data/certs";
            tag = "certs-kanidm";
            proto = "virtiofs";
          }
        ];
      };
    };
  };
}
