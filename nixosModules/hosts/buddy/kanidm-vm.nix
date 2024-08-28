{ flake, profiles, home-configurations, ... }: {
  sops.secrets."kanidm-vm/ssh_host_ed25519_key" = {
    mode = "0400";
  };

  # Kanidm state is basically an SQLite database. This dataset is tuned for that use case.
  disko.devices.zpool.zstorage.datasets."vm/kanidm" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/vm/kanidm"; # Default, but good to be explicit
      logbias = "latency";
      recordsize = "64K";
    };
  };

  microvm.vms.kanidm = {
    autostart = true;
    specialArgs = { inherit flake profiles; };

    # The configuration for the MicroVM.
    # Multiple definitions will be merged as expected.
    config = { config, profiles, ... }: {
      _file = ./kanidm-vm.nix;

      imports = [
        profiles.qemu-guest-vm
        ../SSO.nix # VM config
      ];

      config = {
        _module.args.home-configurations = home-configurations;
        # TODO
        _module.args.facts = { }; #configuration-facts;

        networking.hostName = lib.mkForce "SSO";

        # ERROR; Number must be unique for each VM!
        # NOTE; This setting enables a bidirectional socket AF_VSOCK between host and guest.
        microvm.vsock.cid = 300;

        microvm.interfaces = [{
          type = "tap";
          id = "tap-kanidm";
          mac = "9e:30:e8:e8:b1:d0";
        }];

        microvm.shares = [
          {
            source = "/run/secrets/kanidm-vm";
            mountPoint = "/seeds";
            tag = "container_kanidm";
            proto = "virtiofs";
          }
          {
            source = "/vm/kanidm";
            mountPoint = "/data/state";
            tag = "state-kanidm";
            proto = "virtiofs";
          }
          {
            source = "/var/lib/microvms/kanidm/certs";
            mountPoint = "/data/certs";
            tag = "certs-kanidm";
            proto = "virtiofs";
          }
        ];

        services.openssh.hostKeys = [
          {
            path = "/seeds/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";
      };
    };
  };
}
