{
  lib,
  utils,
  pkgs,
  config,
  ...
}:
let
  pictures-basepath = "/chroot/pictures";
in
{
  systemd.tmpfiles.settings."10-chroot" = {
    # All remote users share the same chroot. An individual home directory is not necessary.
    # Useful data is mounted into the chroot.

    "/chroot" = {
      d = {
        # REF; https://wiki.archlinux.org/title/SFTP_chroot#Setup_the_filesystem
        user = "root";
        group = "root";
        mode = "0755";
      };
      h.argument = "i"; # Immutable (chattr)
    };
    "/chroot/pictures".d = {
      # Empty, only create no change
    };

    # DEBUG
    "/tmp/mounting-test".d = {
      user = "freddy";
      group = "freddy";
      mode = "0755";
    };
  };

  # Freddy target
  users.users.freddy = {
    # Allow interactive logon
    isNormalUser = true;
    description = "Storage mounting over network as Freddy";
    # NOTE; Relative to SSH chroot!
    home = "/";
    createHome = false;
    group = config.users.groups.freddy.name;
    extraGroups = [ config.users.groups.sftpusers.name ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZc+ep5FbHyRSQSmQRjln4fy8NZ/mnOHtw2e3W123WW root@freddy"
    ];
  };
  users.groups.freddy = { };
  users.groups.sftpusers = { };

  systemd.mounts = [
    # NOTE; This configuration with system bind-mounting currently works, but could be locked down further with more effort.
    {
      wantedBy = [
        "multi-user.target"
        # Reload on nixos-rebuild switch
        # ERROR; RestartTriggers with system toplevel derivation does not work! Infinite recursion..
        "sysinit-reactivation.target"
      ];
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [ "sysinit-reactivation.target" ];
      what = "/run/current-system/sw";
      where = "/chroot/run/current-system/sw";
      type = "none";
      options = lib.concatStringsSep "," [ "bind" ];
      unitConfig.RequiresMountsFor = [ "/run/current-system/sw" ];

    }
    {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      what = "/nix/store";
      where = "/chroot/nix/store";
      type = "none";
      options = lib.concatStringsSep "," [ "bind" ];
      unitConfig.RequiresMountsFor = [ "/nix/store" ];
    }
    {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      what = "/dev";
      where = "/chroot/dev";
      type = "none";
      options = lib.concatStringsSep "," [ "bind" ];
      unitConfig.RequiresMountsFor = [ "/dev" ];
    }
    # DEBUG
    {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      what = "/tmp/mounting-test";
      where = pictures-basepath;
      type = "none";
      options = lib.concatStringsSep "," [
        # NOTE; The immich directory has sub-mounts that we want to make accessible (recursive bind)
        "rbind"
      ];
      unitConfig.RequiresMountsFor = [ "/tmp/mounting-test" ];
    }
    # TODO IMMICH Pictures
    # {
    #   wantedBy = [ "multi-user.target" ];
    #   what = "/var/lib/immich";
    #   where = pictures-basepath;
    #   type = "none";
    #   options = lib.concatStringsSep "," [
    #     # NOTE; The immich directory has sub-mounts that we want to make accessible (recursive bind)
    #     "rbind"
    #   ];
    #   unitConfig.RequiresMountsFor = [ "/var/lib/immich" ];
    # }
  ];

  services.openssh = {
    allowSFTP = true;
    # WARN; Built-in sftp server so special bind-mounting isn't required
    sftpServerExecutable = "internal-sftp";
    sftpFlags = [
      "-f AUTH" # Facility for logs with sensitive data
      "-l INFO" # Log SFTP commands
    ];

    extraConfig = ''
      Match User ${config.users.users.freddy.name}
        ChrootDirectory /chroot
        # NOTE; _only_ allow sftp when the user signs-in, but we want the user to be able to:
        #   - SFTP
        #   - Execute ls/hash/stat on files
        #   - zfs-receive
        # ForceCommand internal-sftp -u 0027
        AllowTcpForwarding no
        X11Forwarding no
    '';
  };

  environment.systemPackages = [ ];
}
