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
