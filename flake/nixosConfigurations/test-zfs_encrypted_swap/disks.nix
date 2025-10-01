{ lib, config, ... }:
let
  sshPackage = config.programs.ssh.package;
in
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

    initrd = {
      systemd = {
        enable = true;
        emergencyAccess = true;
        network.wait-online = {
          enable = true;
          anyInterface = true;
        };
        # Configure interfaces during boot the same as while the host runs.
        network.networks = config.systemd.network.networks;
        network.links = config.systemd.network.links;

        # NOTE; The system network configuration should have been captured for initrd too
        # network = {};
        storePaths = [
          # Required for initrd ssh service
          "${sshPackage}/bin/ssh-keygen"
          # Required for IP info at boot
          "${config.boot.initrd.systemd.package}/bin/networkctl"
        ];

        services.sshd = {
          # Updates the sshd service to generate a new hostkey on-demand
          preStart = ''
            ${sshPackage}/bin/ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
          '';
        };

        services.log-network-status = {
          wantedBy = [ "initrd.target" ];

          after = [
            # One adapter initialised
            "network.target"
          ]
          ++ (lib.optionals (config.boot.initrd.systemd.network.wait-online.enable) [
            # "Online" networking status
            "systemd-networkd-wait-online.service"
          ]);
          before = [
            "initrd-switch-root.target"
            "shutdown.target"
          ];
          conflicts = [
            "initrd-switch-root.target"
            "shutdown.target"
          ];

          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal+console";
            ExecStart = [
              "${config.boot.initrd.systemd.package}/bin/networkctl status"
            ];
            Restart = "on-failure";
          };
        };
      };

      network = {
        enable = true;
        ssh = {
          enable = true;
          # To prevent ssh clients from freaking out because a different host key is used,
          # a different port for ssh is useful (assuming the same host has also a regular sshd running)
          port = 2222;
          hostKeys = [
            # Doesn't work for shit, weird documentation and general lack of affordance.
            # Key is provided out-of-band.
            # SEEALSO; boot.initrd.systemd.services.sshd
            # SEEALSO; boot.initrd.network.ssh.extraConfig
          ];
          ignoreEmptyHostKeys = true;
          # Could alternatively have used argument "-h" when starting sshd
          # SEEALSO; boot.initrd.systemd.services.sshd
          extraConfig = ''
            HostKey /etc/ssh/ssh_host_ed25519_key
          '';
          authorizedKeys = [
            # After login and tty construction, switch to- and block on completion of the initrd flow. AKA wait until initrd.target
            # activates, which requires password prompt completion.
            # The password prompts use "systemd-ask-password" to block the boot continuation. Systemd executes systemd-tty-ask-password-agent
            # on each tty so the password(s) can be provided interactively. The SSH session also has a virtual tty now. AKA upon login
            # you're asked to enter the password(s) and the session will reset after succesful unlock.
            #
            # NOTE; systemctl default == systemctl isolate default.target
            # NOTE; the unit systemd-ask-password-console.service is responsible for launching the password agent on tty's
            "command=\"systemctl default\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILEeQ/KEIWbUKBc4bhZBUHsBB0yJVZmBuln8oSVrtcA5 bert@B-PC"
          ];
        };
      };
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
        # NOTE; Stage-1 force loads encryption keys for all encrypted datasets during pool import. The _order_ of import is
        # important to prevent pool-import failure and halting boot.
        # WARN; `zfs list` by default sorts on 'creation' property, the pool-import script does not define a sorting.
        # REF; https://github.com/NixOS/nixpkgs/blob/6310777266905c286a48893c48274b7efafc8772/nixos/modules/tasks/filesystems/zfs.nix#L225-L248
        #
        # WARN; Something in Disko (or nix, maybe attr-merge has sorting side-effect) does an alphabetical sort of the dataset names
        # before they end up inside the diskoScript (creation script). The datasets are created in alphabetical order by full dataset path.
        # This means we must update the dataset names to get a proper key loading order!
        "a-encryptedroot" = {
          # Encryptionroot for the root filesystem, basically everything local to the system unimportant to backup.
          type = "zfs_fs";
          options = {
            mountpoint = "legacy";
            encryption = "aes-256-gcm";
            keyformat = "passphrase";
            keylocation = "prompt";
            pbkdf2iters = "500000";
          };
          mountpoint = "/";
          mountOptions = [ "defaults" ];
        };
        "a-encryptedroot/nix" = {
          type = "zfs_fs";
          options.mountpoint = "legacy";
          mountpoint = "/nix";
        };

        # Refer to this logical partition by "/dev/zvol/zroot/a-encryptedroot/zram-backing-device"
        #
        # NOTE; The /dev/zvol symlink comes from UDEV rules delivered by the ZFS package.
        # WARN; UDEV generates a directory tree when it encounters forward slashes(/), contrary to systemd where
        # special path characters are encoded!
        # REF; https://github.com/openzfs/zfs/blob/8869caae5f6558b056d86aeae6d605df27086813/udev/rules.d/60-zvol.rules.in
        # REF; https://github.com/openzfs/zfs/blob/cb3c18a9a93dcff9b18f48b72aafcc06342c63e3/udev/zvol_id.c
        "a-encryptedroot/zram-backing-device" = {
          type = "zfs_volume";
          size = "1G";
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

        "b-encryptedroot" = {
          # Encryptionroot for all datasets with program/userdata. I want this backed up!
          #
          # Datasets are encrypted with a unique masterkey, but the encryptionroot defines how those master keys themselves are
          # en-/decrypted! To prevent footguns the encryptionroot (and descending datasets) becomes the smallest unit to backup!
          # There is the option to turn each dataset into its own encryptionroot which allows for more flexible backup schedule
          # considering each individual dataset, but that is a lot more hassle with encryption keys for no functional gain.
          #
          # HELP; Create a new encryptionroot for each unique backup schema.
          # REF; https://sambowman.tech/blog/posts/mind-the-encryptionroot-how-to-save-your-data-when-zfs-loses-its-mind/
          type = "zfs_fs";
          options = {
            canmount = "off";
            mountpoint = "none";
            encryption = "aes-256-gcm";
            keyformat = "passphrase"; # Swapped after creation, see below
            keylocation = "prompt";
            pbkdf2iters = "500000";
          };
          postCreateHook = ''
            # zfs set keylocation="<url[http://|file://]>" "<fully qualified dataset path>"
            # TODO; Deploy passphrase file to root filesystem
            zfs set keylocation="file:///etc/secrets/secret.key" "zroot/b-encryptedroot"
          '';
        };

        "dataencryptedroot/userdata" = {
          # One of the storage locations.
          #
          # HELP; Create a new dataset for each unique mountpoint, and unique filesystem needs, and reducing denial-of-service-attack
          # risk.
          type = "zfs_fs";
          mountpoint = "/userdata";
          options = {
            mountpoint = "/userdata";
          };
        };
      };
    };
  };
}
