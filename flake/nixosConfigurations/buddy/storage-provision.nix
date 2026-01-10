{
  lib,
  pkgs,
  config,
  ...
}:
let
  pictures-basepath = "/chroots/freddy/pictures";
in
{
  systemd.tmpfiles.settings."10-chroots" = {
    # Prepare the filesystem so sub-trees can become externally mounted!
    "/chroots".d = {
      user = "root";
      group = "root";
      mode = "0555"; # a+rx
    };

    "/chroots/freddy".d = {
      user = "root";
      group = "root";
      # ERROR; Chroot directory _must_ be owned by root/another user as a security best-practice!
      mode = "0555"; # a+rx
    };

    "/chroots/freddy/pictures".d =
      assert "/chroots/freddy/pictures" == pictures-basepath;
      {
        user = "freddy";
        group = "freddy";
        mode = "0700"; # u+rwx
      };
  };

  users.groups.sftpusers = { };

  # Freddy target
  users.users.freddy = {
    # Allow interactive logon
    isNormalUser = true;
    description = "Storage mounting over network as Freddy";
    # Do not give the opportunity for writeable storage
    home = "/chroots/freddy";
    createHome = false;
    group = "freddy";
    extraGroups = [ config.users.groups.sftpusers.name ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZc+ep5FbHyRSQSmQRjln4fy8NZ/mnOHtw2e3W123WW root@freddy"
    ];
  };
  users.groups.freddy = { };

  systemd.mounts = [
    {
      # Freddy host
      wantedBy = [ "default.target" ];
      requires = [ "zfs-import.target" ];
      after = [
        "systemd-tmpfiles-setup.service"
        "zfs-import.target"
      ];
      what = "/var/lib/immich";
      where = pictures-basepath;
      type = "fuse.bindfs";
      options = lib.concatStringsSep "," [ ];
      unitConfig = {
        RequiresMountsFor = [ "/var/lib/immich" ];

        # ERROR; _Remounting_ this unit will fail!
        # Systemd will pass '-o remount' to fuse, which does not support the remount option like the underlying mount
        # command does!
        # You must stop the mount and remount (or reboot the machine) to get your mount changes active!
        #
        # WARN; Stopping the unit is also skipped to prevent losing data in-flight!
        X-ReloadIfChanged = false;
        X-RestartIfChanged = false;
        X-StopIfChanged = false;
        X-StopOnReconfiguration = false;
        X-StopOnRemoval = false;
      };
    }
    # TODO IMMICH Pictures
  ];

  services.openssh = {
    allowSFTP = true;
    sftpFlags = [
      "-f AUTH" # Facility for logs with sensitive data
      "-l INFO" # Log SFTP commands
    ];

    extraConfig = ''
      Match User ${config.users.users.freddy.name}
        ChrootDirectory /chroots/freddy
        # NOTE; _only_ allow sftp when the user signs-in, but we want the user to be able to:
        #   - SFTP
        #   - Execute ls/hash/stat on files
        #   - zfs-receive
        # ForceCommand internal-sftp -u 0077
        AllowTcpForwarding no
        X11Forwarding no
    '';
  };

  environment.systemPackages = [
    pkgs.bindfs # For bind mounting
  ];
  # boot.supportedFilesystems."fuse.bindfs" = true;

}
