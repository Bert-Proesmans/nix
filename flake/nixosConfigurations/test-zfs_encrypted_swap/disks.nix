{ ... }:
{
  boot = {
    kernelParams = [
      "nohibernate"
      # 500MiB (bytes)
      "zfs.zfs_arc_max=524288000"
    ];
    # supportedFilesystems = [ "zfs" ];
    zfs = {
      devNodes = "/dev/";
      forceImportRoot = false;
      requestEncryptionCredentials = true;
    };
    loader.systemd-boot = {
      enable = true;
      editor = true; # DEBUG
    };
  };

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  disko.devices = {
    disk.first = {
      type = "disk";
      device = "/dev/sda";
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
      rootFsOptions = {
        mountpoint = "none";
        canmount = "off";
        compression = "zstd";
        acltype = "posixacl";
        xattr = "sa";
        "com.sun:auto-snapshot" = "false";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          options = {
            mountpoint = "legacy";
            encryption = "aes-256-gcm";
            keyformat = "passphrase";
            #keylocation = "file:///tmp/secret.key";
            keylocation = "prompt";
            pbkdf2iters = "500000";
          };
          mountpoint = "/";
          mountOptions = [ "defaults" ];
        };
        "root/nix" = {
          type = "zfs_fs";
          # options.mountpoint = "/nix";
          options.mountpoint = "legacy";
          mountpoint = "/nix";
        };

        # README MORE: https://wiki.archlinux.org/title/ZFS#Swap_volume
        "root/swap" = {
          type = "zfs_volume";
          size = "1G";
          # Refer to this logical partition by "/dev/zvol/zroot/zram-backing-device"
          name = "zram-backing-device";
          options = {
            refreservation = "1G";
            # WARN; Should match result of command $(getconf PAGESIZE)
            volblocksize = "4096";
            compression = "zle";
            logbias = "throughput";
            sync = "always";
            primarycache = "metadata";
            secondarycache = "none";
            # NOTE; DIRECT I/O currently not supported with zvols.
            # direct = "always"; # ERROR; Setting this option will fail creation!
          };
        };
        # encrypted = {
        #   type = "zfs_fs";
        #   options = {
        #     mountpoint = "none";
        #     encryption = "aes-256-gcm";
        #     keyformat = "passphrase";
        #     keylocation = "file:///tmp/secret.key";
        #   };
        #   # use this to read the key during boot
        #   # postCreateHook = ''
        #   #   zfs set keylocation="prompt" "zroot/$name";
        #   # '';
        # };
        # "encrypted/test" = {
        #   type = "zfs_fs";
        #   mountpoint = "/zfs_crypted";
        # };
      };
    };
  };
}
