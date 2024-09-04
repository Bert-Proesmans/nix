{ lib, config, ... }: {
  # Define the platform type of the target configuration
  nixpkgs.hostPlatform = lib.systems.examples.gnu64;

  # Enables (nested) virtualization through hardware acceleration.
  # There is no harm in having both modules loaded at the same time, also no real overhead.
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = true;

  # Generated with `head -c4 /dev/urandom | od -A none -t x4`
  # NOTE; The hostId is a marker that prevents ZFS from importing pools coming from another system.
  # It's best practise to mark the pools as 'exported' before moving them between systems.
  # NOTE; Force importing is possible, ofcourse.
  networking.hostId = "525346fb";
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  disko.devices.zpool.local.datasets = {
    "root" = {
      # Root filesystem, a catch-all
      type = "zfs_fs";
      mountpoint = "/";
      postCreateHook = ''
        # Generate empty snapshot in preparation for impermanence
        zfs list -t snapshot -H -o name | grep -E '^local/root@empty$' || zfs snapshot 'local/root@empty'
      '';
      options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
    };
    #"persist" = {
    # In preparation for impermanence
    #};
    "persist/logs" = {
      # Stores systemd logs
      type = "zfs_fs";
      mountpoint = "/var/log";
      options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
    };
    "nix" = {
      # Nix filestore, contains no state
      type = "zfs_fs";
      mountpoint = "/nix";
      options = {
        atime = "off"; # nix store doesn't use access time
        sync = "disabled"; # No sync writes
        # NOTE; The nix store is shared into virtual machines by virtiofs. Virtiofs requires 
        # the presence of acl metadata in our dataset
        # acltype = "off"; # set to off if there is no virtiofs in use
        acltype = "posixacl";
        xattr = "sa";
        mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
      };
    };
    "nix/reserve" = {
      # Reserved space to allow copy-on-write deletes
      type = "zfs_fs";
      mountpoint = null;
      options = {
        canmount = "off";
        # Reserve disk space for files without incorporating snapshot and clone numbers.
        # WARN; Storage statistics are (almost) never straight up "this is the sum size of your data"
        # and incorporate reservations, snapshots, clones, metadata from self+child datasets.
        refreservation = "1G";
      };
    };
    "temporary" = {
      # Put /var/tmp on a separate dataset to curb its usage (if needed)
      type = "zfs_fs";
      # NOTE; /var/tmp (and /tmp) are subject to automated cleanup
      mountpoint = "/var/tmp";
      options = {
        compression = "lz4"; # High throughput lowest latency
        #sync = "disabled"; # No sync writes
        devices = "off"; # No mounting of devices
        setuid = "off"; # No hackery with user tokens on this filesystem
      };
    };
  };

  systemd.network.links = {
    "10-upstream" = {
      matchConfig.MACAddress = "b4:2e:99:15:33:a6";
      linkConfig.Alias = "Internet uplink";
      linkConfig.AlternativeName = "main";
    };
  };

  systemd.network.networks = {
    "30-lan" = {
      matchConfig.MACAddress = "b4:2e:99:15:33:a6";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
