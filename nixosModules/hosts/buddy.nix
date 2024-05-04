{ lib, config, profiles, ... }: {

  imports = [ profiles.hypervisor ];

  networking.hostName = "buddy";
  networking.domain = "alpha.proesmans.eu";

  proesmans.nix.linux-64 = true;
  proesmans.nix.garbage-collect.enable = true;
  proesmans.internationalisation.be-azerty.enable = true;
  proesmans.home-manager.enable = true;

  # Prevent replacing the running kernel w/o reboot
  security.protectKernelImage = true;

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
  # Leave ZFS pool alone!
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # ZFS setup
  #
  # Creates a RAIDZ1 pool from 3 disks.
  # The pool partitions are aligned and all have a fixed size, the remaining size is kept for swap space.
  # Swap can work in round robin, so each disk provides some amount of swap into the total swap pool.
  #
  # On top of the pools is a dataset buildout for data handling, a mix of snapshot and replication
  # policies, performance, and security go into the design.
  #
  # The ZFS storage partition sizes are set to 3722 Gibibyte (~=3.6 Tebibyte ~= 4.0 Terabyte).
  # That makes ~3 Gibibyte available for other purposes (boot/swap) and rounding errors.
  #
  # ZFS is given partitions instead of entire disks. There is nothing inherently wrong with that
  # approach, nothing will break.
  #
  # Partition alignment is no problem under the circumstances below. Both start- and end alignment is
  # provided by the software (s)gdisk.
  # - sgdisk tries to align by default on 2048 * sectors (aka flash/data pages), assuming 512-byte sectors
  #   means 1 mebibyte
  #   - if the disk reports bigger sector sizes, the 2048 sector alignment is recalculated to
  #     a multiple of 8 sectors with target around 1 mebibyte
  # - don't calculate in sectors manually
  # - don't work with sizes less than 1 mebibyte
  #
  # If the disks, anno 2024, do not contain 4096-byte sectors they contain 8192-byte pages. 1 mebibyte is
  # a multiple of both 4096 and 8192 bytes, which means going for 8192 alignment (ashift=13) will not
  # introduce performance issues due to misalignment.
  # There is no performance loss because the sector sizes are used as a unit of contiguous writes. The reverse,
  # smaller contiguous writes than physical sectors, will induce a performance penalty because of the
  # copy+update+overwrite cycle _per write_.
  #
  # These are the considerations for running ZFS on partitionss;
  # - Disk access is shared between ZFS and other processes using the same disk. ZFS will be unaware of
  #   the other software accessing the disk, and cannot be made aware of this happening.
  # - The kernel performs (fairness) access scheduling for each disk. When giving disks to ZFS
  #   it automatically disables this I/O scheduler. Disable this manually for a bit of latency
  #   improvement.
  #
  # With the consideration that every disk is either an SSD/NVME or managed through ZFS it's
  # better to disable the scheduler by default for all disks ({ boot.kernelParams = [ "elevator=none" ]; }).
  # Manually enable the scheduler again per-disk that requires it.
  disko.devices = {
    disk.slog = {
      type = "disk";
      device = "/dev/disk/by-id/ata-M4-CT128M4SSD2_00000000114708FF549B";
      content = {
        type = "gpt";
        partitions = {
          slog = {
            size = "4G";
            name = "for-zstorage"; # Refer to this partition using '/dev/disk/by-partlabel/disk-slog-for-zstorage'
          };
        };
      };
    };
    disk.local-one = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKKW256G7_BTPY64630GRV256D";
      content = {
        type = "gpt";
        partitions = {
          one = {
            type = "BF01";
            size = "200G";
            content = {
              type = "zfs";
              pool = "zlocal";
            };
          };
        };
      };
    };
    # Using `boot.loader.grub.mirroredBoots` (GRUB bootloader) to keep the boot data in sync accross disks.
    # I much prefer the clean presentation of systemd-boot though ..
    disk.raid-one = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFPX-68C6CN0_WD-WX22D93FVL17";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/0"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "zstorage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };
    disk.raid-two = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3VE4XDK";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/1"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "zstorage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };
    disk.raid-three = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0EYF88K";
      content = {
        type = "gpt";
        partitions = {
          # for grub MBR
          boot = {
            type = "EF02";
            size = "1M";
          };
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/2"; # WARN; Unique per disk!
              mountOptions = [ "nofail" "x-systemd.device-timeout=5" ];
            };
          };
          root = {
            type = "BF01";
            size = "3722G";
            content = {
              type = "zfs";
              pool = "zstorage";
            };
          };
          #
          swap = {
            size = "100%";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
        };
      };
    };

    # ZFS pool optimised for my spinning rust setup
    zpool.zstorage = {
      type = "zpool";
      mode = "raidz";
      mountpoint = null; # Don't (automatically) mount the pool filesystem
      postCreateHook = ''
        # Add SLOG device manually (not yet abstracted by DISKO)
        zpool add zstorage log '/dev/disk/by-partlabel/disk-slog-for-zstorage'
      '';
      # Configure the pool
      options = {
        # Set to 8KiB in preparation of NVMe vdev members. There is (also) no downside to making maximum write chunksize larger
        # than physical sector size.
        ashift = "13";
        autotrim = "on";
      };
      # Configure the pool (aka pool-root aka dataset-parent) filesystem.
      # WARN; These settings are automatically inherited
      rootFsOptions = {
        # NOTE; No mounting/auto-mounting
        canmount = "off";
        # NOTE; Datasets do not inherit a parent mountpoint.
        # Default; Name of pool, 'zpool' in this case
        mountpoint = "none";
        # NOTE; Fletcher is by far the fastest
        # Only change checksumming algorithm if dedup is a requirement, blake3 is a cryptographic
        # hasher for higher security on clash resistance
        checksum = "fletcher4";
        # NOTE; ZSTD-1 mode, performs better compression with ballpark same throughput of LZ4.
        # Doesn't require overwriting on sub-datasets
        compression = "zstd-fast-1";
        # NOTE; Enable extended access control lists because owner/group/other is restrictive as frick!
        acltype = "posixacl";
        # NOTE; Store file metadata as extensions in inode structure (for performance)
        xattr = "sa";
        # NOTE; Increase inode size, if ad-hoc necessary, from the default 512-byte
        dnodesize = "auto";
        # NOTE; Enable optimized access time writes
        # HELP; Disable access time selectively per dataset
        relatime = "on";
        # NOTE; Make standard record size explicit
        # NOTE; Within hard disk pools it's better to go for bigger recordsizes to optimize away the static
        # seek time latency. But this improves the ratio of latency while increasing the average latency.
        # HELP; Change record size per dataset, there are various online sources with information
        # HELP; If application level caching is present, push the recordsize upwards
        recordsize = "128K";
        # NOTE; Compare filenames after normalizing using KC unicode conversion table. This turns characters into
        # equivalent characters; fullwidth "Ａ" (U+FF21) -> "A" (U+0041) [lossy conversion!!]
        normalization = "formKC";
        # NOTE; Activate ZIL direct mode. This reduces pool fragmentation while burning through an (old) SSD SLOG device.
        # NOTE; ZIL blocks (aka the journal) are ephemeral, after the transaction commit they are erased. If those blocks were written
        # to the data vdevs, this causes data holes of various sizes aka bad fragmentation.
        # NOTE; Continuous and/or random writes are collected into the ZIL until a continuous block of `recordsize` data is present. Then
        # that data gets written to the data vdevs on next commit (or filesystem sync request). The ZIL is part of the pool, but `recordsize`
        # depends on the target dataset configuration.
        # AKA; A bittorrent client might be performing small random writes accross the files until downloading completes, but the to-disk
        # behaviour of ZFS is not actually that small nor random! (Given there is no program requesting filesystem syncs)
        #
        # Bias ZIL on throughput
        # When ZIL indirect mode writes records to the data vdevs, it writes data blocks to the data vdevs too. The data is 
        # 'already at the desired offset into the pool', will not move anymore unless unlinked, and pointers to 
        # those locations are stored into the ZIL journal. The effect being less disk seeks and less reads on asynchronous writes.
        # Synchronous writes will take the perfmance hit of a fragmented pool, and during cleanup operations of the async writes.
        #
        # Bias ZIL on latency
        # ZIL direct (synchronous) mode duplicates all data (up to size defined by zfs_immediate_write_sz) into the ZIL journal.
        # Latency is (supposed to be) lower because the write operation returns after persisting the journal, which is either 
        # on the data vdevs or SLOG.
        # ZIL operations are a single threaded operation. Writting the ZIL to an SSD special device improves latency, but not necessary
        # throughput. Then a ZIL on pool performs better.
        #
        # Optimizing the pool into a default mode and custom config for specific dataloads is hard, better is to simplify incorporating
        # the pool layout and physical device performance. Datasets should be designed to cluster related synchronous writes as much as possible.
        # My needs are very likely best served by the defaults, so try to keep configuration default as much as possible.
        #
        # My pool is a basic setup of RAIDZ1 HDD's and SLOG, where my burst traffic is less than 1 GiB of data, and average file size
        # should be >500 KiB. Except for database operations.
        #
        # So I configure ZIL bias on latency, and setup bias for throughput on datasets with bigger record size writes. The parameter
        # zfs_immediate_write_sz (transform a write from sync into async) only comes in effect when the SLOG drops out of the pool,
        # so not useful in the average case.
        # The SSD burn rate will be directly correlated to the write patterns on the (preferrably) few datasets that 
        # _are configured with latency bias_.
        #
        # WARN; Always use an SLOG, because the ZIL is always created and consequently stored on the data vdevs (disks)
        # if no special device is attached to the pool.
        # An indirect sync (happens on big file size writes), or setting logbias to throughput, will cause fragmentation 
        # between data and related metadata. A steady state pool will encounter double/triple read overhead 
        # due to this fragmentation. Consider burning away old SSD's for this purpose, only ~4GiB is necessary
        # and keep the rest overprovisioned. Erase first, use 'blkdiscard' to trim all sectors of the drive!
        #
        logbias = "latency";
        # NOTE; Enable record sizes larger than 128KiB
        "org.open-zfs:large_blocks" = "enabled";
        # NOTE; Opt out of built-in snapshotting, sanoid is used
        "com.sun:auto-snapshot" = "false";
      };
      # NOTE; You can create nested datasets without defining any parent. The parent datasets will exist ephemerally
      # and be automatically configured from the parent-parent dataset or pool-filesystem options.
      # Explicitly defining parent datasets becomes interesting to change a default option that will apply
      # automatically to all child datasets.
      #
      # ERROR; The following paths must exist before systemd is started!
      # pathsNeededForBoot = [ "/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr" ];
      # REF; https://github.com/linj-fork/nixpkgs/blob/master/nixos/lib/utils.nix#L13
      # The datasets that mount on those paths will be loaded during stage-1-boot under the zpool import action. The zpool import
      # happens before changing root, but ZFS is unaware of the soon-to-be root.
      # Nix automatically calculates the required mounts for the above paths, and will manually mount the datasets on the
      # soon-to-be root. An error will occur if that dataset was auto-mounted by pool import, so the dataset needs option
      # 'mountpoint=legacy' to prevent this.
      #
      # WARN; Switching root will unmount everything recursively and swap into the new root filesystem. That means the datasets
      # that were automounted are unmounted again. After systemd start, there is a single unit "zfs-mount.service" that remounts
      # those datasets.
      # If there are random boot failures, this could indicate a mount ordering issue in the context of systemd service units.
      # Systemd could be helpful and create paths for services, basically racing the zfs-mount service. The problem typically is
      # lack of ordering between units.
      # There is an upstream solution (i think, dunno what it exactly does) called ZFS automount generator (generators are a systemd
      # concept). This presumably solves shizzle? The ZFS automount generator script hasn't been turned into nixos options yet,
      # but it is accessible through the ZFS upstream package. So try it out, maybe it helps.
      #
      datasets = {
        #"local" = {};
        "local/root" = {
          # Root filesystem, a catch-all
          type = "zfs_fs";
          mountpoint = "/";
          postCreateHook = ''
            # Generate snapshot in preparation for impermanence
            zfs list -t snapshot -H -o name | grep -E '^zstorage/local/root@empty$' || zfs snapshot 'zstorage/local/root@empty'
          '';
          options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
        };
        "local/var" = {
          # Services data, contains state and logs
          type = "zfs_fs";
          mountpoint = "/var";
          options.mountpoint = "legacy"; # Filesystem at boot required, prevent duplicate mount
        };
        #"safe" = { };
        #"safe/persist" = {
        # "safe/persist/vm" = {
        "safe/persist/vm/state" = {
          # Stores all state between reboots in a single location
          # at file/folder granularity
          type = "zfs_fs";
          options = {
            mountpoint = "/vm-state";
            # Qemu does its own application level caching
            # NOTE; Set to none if you'd be storing raw- or qcow backed volumes.
            primarycache = "metadata";
            # Asynchronous IO for maximal volume performance
            logbias = "throughput";
            # Haven't done benchmarking to change away from the default
            recordsize = "128K";
            # ACL required for virtiofs
            acltype = "posixacl";
            xattr = "sa";
            # 
            devices = "off";
            setuid = "off";
          };
        };
        "safe/home" = {
          # User data
          type = "zfs_fs";
          # WARN; Potential race while mounting, see the note about zfs generators
          # REF; https://github.com/NixOS/nixpkgs/issues/212762
          mountpoint = "/home";
          # Workaround sync hang with SQLite WAL
          # REF; https://github.com/openzfs/zfs/issues/14290
          # See also `overlays.atuin`!
          # options.sync = "disabled";
        };
        "replicate" = {
          # State to be sent/received from cluster
          type = "zfs_fs";
          mountpoint = "/replicate";
        };
      };
    };

    # ZFS pool, mostly default, for modern COW filesystem for local data.
    # Main use case is storing the nix store.
    zpool.zlocal = {
      type = "zpool";
      # ERROR; Intentionally left empty to not create a VDEV. No vdev explicitly creates
      # a non-redundant pool (aka RAID0)!
      mode = "";
      mountpoint = null;
      options = {
        # Set to 8KiB because of NVMe vdev members.
        ashift = "13";
        autotrim = "on";
      };
      # Configure the pool (aka pool-root aka dataset-parent) filesystem.
      # WARN; These settings are automatically inherited
      rootFsOptions = {
        # NOTE; No mounting/auto-mounting
        canmount = "off";
        # NOTE; Datasets do not inherit a parent mountpoint.
        mountpoint = "none";
        # NOTE; Opt out of built-in snapshotting, sanoid is used
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        #"local" = {};
        "local/nix" = {
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
        "local/temporary" = {
          type = "zfs_fs";
          mountpoint = "/tmp";
          options = {
            compression = "lz4"; # High throughput lowest latency
            sync = "disabled"; # No sync writes
            devices = "off"; # No mounting of devices
            setuid = "off"; # No hackery with user tokens on this filesystem
          };
        };
      };
    };
  };

  boot.kernelParams = lib.optionals (config.boot.zfs.enabled) [
    # Set default I/O (disk) scheduler to `none` for all disks.
    # ERROR; Kernel argument doesn't work anymore, use UDEV rules to apply the correct I/O scheduler!
    # NOTE; Since 23.11, NixOS includes the necessary UDEV rules
    # FAILS "elevator=none"

    # Workaround for openzfs/zfs issue #9810
    # "spl.spl_taskq_thread_dynamic=0"
  ];

  # Tune ZFS
  boot.extraModprobeConfig = ''
    # Fix the commit timeout (seconds), because the default has changed before
    options zfs zfs_txg_timeout=5

    # This is a hypervisor server, and ZFS ARC is sometimes slow with giving back RAM.
    # It defaults to 50% of total RAM, but we fix it to 8 GiB (bytes)
    options zfs zfs_arc_max=8589934592

    # Data writes less than this amount (bytes) are written in sync, while writes larger are written async.
    # ERROR; Only has effect when no SLOG special device is attached to the pool to be written to.
    #
    # ERROR; Data writes larger than the recordsize are automatically async, to prevent complexities while handling
    # multiple block pointers in a ZIL log record.
    # Set this value equal to or less than the largest recordsize written on this system/pool.
    options zfs zfs_immediate_write_sz=1048576

    # Enable prefetcher. Zfs proactively reads data from spinning disks, expecting inflight or future requests, into
    # the ARC.
    options zfs zfs_prefetch_disable=0
  '';

  # this is both efi and bios compatible
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    # Uses convention instead of explicitness between EFI firmware and this operating system.
    efiInstallAsRemovable = true;
    # WARN; Something (disko?) adds devices to this array. We're using multiple boot partitions, defined
    # below, which get accumulated into effectively installing grub twice on each disk.
    # These devices are forced empty so the grub install won't produce warnings/errors.
    devices = lib.mkForce [ ];
    mirroredBoots = [
      {
        devices = [ "nodev" ];
        path = "/boot/0";
      }
      {
        devices = [ "nodev" ];
        path = "/boot/1";
      }
      {
        devices = [ "nodev" ];
        path = "/boot/2";
      }
    ];
  };

  services.fstrim.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.interval = "weekly";

  # Make me a user!
  users.users.bert-proesmans = {
    isNormalUser = true;
    description = "Bert Proesmans";
    extraGroups = [ "wheel" ]
      ++ lib.optional config.virtualisation.libvirtd.enable
      "libvirtd" # NOTE; en-GB
      ++ lib.optional config.networking.networkmanager.enable
      "networkmanager";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
    ];
  };

  # Allow for remote management
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Allow privilege elevation to administrator role
  security.sudo.enable = true;
  # Allow for passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  # Networking configuration
  # Allow PMTU / DHCP
  networking.firewall.allowPing = true;

  # Keep dmesg/journalctl -k output readable by NOT logging
  # each refused connection on the open internet.
  networking.firewall.logRefusedConnections = false;

  # Use networkd instead of the pile of shell scripts
  networking.useNetworkd = true;
  # Setup a fixed mac-address on the hypervisor bridge
  systemd.network.netdevs."bridge0" = {
    # ERROR; Must copy in all netdevConfig attribute names because this type of set doesn't merge
    # with other declarations!
    netdevConfig = {
      Name = "bridge0";
      Kind = "bridge";
      MACAddress = lib.facts.buddy.net.management.mac;
    };
  };
  systemd.network.networks = {
    # Attach the physical interface to the bridge. This allows network access to the VMs
    "30-lan" = {
      matchConfig.MACAddress = [ lib.facts.buddy.net.physical.mac ];
      networkConfig = {
        Bridge = "bridge0";
      };
    };
    # The host IP comes from a DHCP offer, the DHCP client must run on/from the bridge interface
    "30-lan-bridge" = {
      matchConfig.Name = "bridge0";
      networkConfig = {
        Address = [ "192.168.100.2/24" ];
        # Gateway = "192.168.100.1";
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
    };
  };

  # The notion of "online" is a broken concept
  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;

  # FIXME: Maybe upstream?
  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
  # followed by a delayed `systemctl start`.
  systemd.services.systemd-networkd.stopIfChanged = false;
  # Services that are only restarted might be not able to resolve when resolved is stopped before
  systemd.services.systemd-resolved.stopIfChanged = false;

  # MicroVM has un-nix-like default of true for enable option, so we need to force it on here.
  microvm.host.enable = lib.mkForce true;
  microvm.vms = {
    # technitium = {
    #   autostart = true;
    #   flake = null;
    #   updateFlake = null;
    #   specialArgs = { inherit profiles; };

    #   config = {
    #     networking.hostName = "DNS";
    #     imports = [ profiles.micro-vm ];

    #     microvm.interfaces = [{
    #       type = "tap";
    #       id = "tap-technitium";
    #       mac = lib.facts.vm.dns.net.mac;
    #     }];

    #     microvm.shares = [{
    #       source = "/vm-state/technitium";
    #       # ERROR; The systemd service is defined with a DynamicUser statement, meaning the
    #       # directory "/var/lib/technitium-dns-server" is a symlink into "/var/lib/private/technitium-dns-server"
    #       # for additional host sandboxing.
    #       # If the service is not run with a dynamic user id, bind the normal "/var/lib/technitium-dns-server" path.
    #       mountPoint = "/var/lib/private/technitium-dns-server";
    #       tag = "technitium";
    #       proto = "virtiofs";
    #     }];

    #     services.technitium-dns-server.enable = true;
    #     services.technitium-dns-server.openFirewall = true;
    #   };
    # };

    # kanidm = {
    #   autostart = true;
    #   flake = null;
    #   updateFlake = null;
    #   specialArgs = { inherit profiles; };

    #   # The configuration for the MicroVM.
    #   # Multiple definitions will be merged as expected.
    #   config = {
    #     networking.hostName = "SSO";
    #     imports = [ profiles.micro-vm ];

    #     # Any other configuration for your MicroVM
    #     # [...]
    #   };
    # };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "23.11";
}

