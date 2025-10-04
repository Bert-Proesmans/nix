{
  lib,
  pkgs,
  config,
  ...
}:
{
  boot.zfs = {
    devNodes = "/dev/";
    forceImportRoot = false;
    forceImportAll = false;
    requestEncryptionCredentials = config.proesmans.facts.self.encryptedDisks;
  };

  boot.extraModprobeConfig = ''
    # Fix the commit timeout (seconds), because the default has changed before
    options zfs zfs_txg_timeout=5

    # It defaults to 50% of total RAM, but we fix the amount of RAM used.
    # 8 GiB (bytes)
    options zfs zfs_arc_max=8589934592
  '';

  services.zfs = {
    autoScrub.enable = true;
    autoScrub.interval = "weekly";
    trim.enable = true;
  };

  # @@ Disk rundown @@
  #   - Partitions, root disk
  #     - /boot
  #     - [ZFS], pool zroot
  #       - encryptionroot, native ZFS encryption
  #         - / (root)
  #         - /nix
  #         - /var/cache
  #         - /var/log
  #         - /persist
  #           - **
  #
  # ** ZFS datasets are optimized per application and mounted straight into the state directory location.

  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda"; # OCI SSD IOPS, HDD throughput (24 MB/s)
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          # NOTE; ZFS pool
          #   => contains encrypted dataset (zroot/encryptionroot)
          #     => contains root filesystem
          #     => contains nix filesystem (split on inode DOS)
          #     => contains user data to replicate
          #       SEEALSO; disko.devices.zpool.zroot.datasets
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };
    zpool.zroot = {
      type = "zpool";
      # NOTE; Single partition, in a single vdev, in pool
      mode = "";
      options.ashift = "12";
      options.autotrim = "on";
      rootFsOptions = {
        canmount = "off";
        mountpoint = "none";
        # HELP; Doesn't require overwriting on sub-datasets unless for specific data optimization
        compression = "zstd-fast-1";
        acltype = "posixacl";
        xattr = "sa";
        # NOTE; Increase inode size, if ad-hoc necessary, from the default 512-byte
        dnodesize = "auto";
        # NOTE; Enable optimized access time writes
        # HELP; Disable access time selectively per dataset
        relatime = "on";
        # NOTE; Make standard record size explicit
        # NOTE; Within hard disk pools it's better to go for bigger recordsizes to optimize away the static seek time latency.
        # But this _only_ improves the ratio of latency to retrieval bandwidth while increasing the average latency.
        # HELP; Change record size per dataset, there are various online sources with information
        # HELP; If application level caching is present, increase the recordsize
        recordsize = "128K";
        # NOTE; Compare filenames after normalizing using KC unicode conversion table. This turns characters into
        # equivalent characters; fullwidth "Ａ" (U+FF21) -> "A" (U+0041) [lossy conversion!!]
        # HELP; Do not overwrite unless good reason to
        normalization = "formKC";
        # NOTE; Enable record sizes larger than 128KiB
        "org.open-zfs:large_blocks" = "enabled";
        "com.sun:auto-snapshot" = "false";
        # Restrict privilege elevation in both directions of host<->guest through file sharing.
        devices = "off";
        setuid = "off";
        exec = "off";
      };

      # Datasets are filesystems, those are defined in ./filesystems.nix for readability.
      datasets = { };
    };
  };

  # ## Enable the ZFS mount generator ##
  #
  # This makes sure that units are properly ordered if filesystem paths inside unitconfig "RequiresMountsFor" are pointing
  # to ZFS datasets.
  #
  # REF; https://openzfs.github.io/openzfs-docs/man/master/8/zfs-mount-generator.8.html#EXAMPLES
  # REF; https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469

  systemd.tmpfiles.settings."00-zfs-pre-fs" = {
    # WARN; The systemd generator phase is early in the boot process, and should add units that order before local-fs!
    # To properly work it should see all mounted pools, but those could not exist.
    # Imperatively discovered, the pool import during stage-1 and stage-2 are not enough for the generator to work due to unknown
    # reason.

    # According to the referenced resource, event caching must be enabled on a per pool basis. Caching is enabled when a file exists
    # at a hardcoded path.
    "/etc/zfs/zfs-list.cache/storage".f = {
      user = "root";
      group = "root";
      mode = "0644";
    };
  };

  systemd.generators."zfs-mount-generator" =
    "${config.boot.zfs.package}/lib/systemd/system-generator/zfs-mount-generator";
  environment.etc."zfs/zed.d/history_event-zfs-list-cacher.sh".source =
    "${config.boot.zfs.package}/etc/zfs/zed.d/history_event-zfs-list-cacher.sh";
  systemd.services.zfs-mount.enable = false;

  services.zfs.zed.settings.PATH = lib.mkForce (
    lib.makeBinPath [
      pkgs.diffutils
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nettools
      pkgs.util-linux
    ]
  );
}
