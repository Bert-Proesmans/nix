{
  lib,
  pkgs,
  config,
  ...
}:
{
  disko.devices.zpool.storage.datasets = {
    "backup/freddy" = {
      # NOTE; Container for child datasets created by freddy host
      #
      # Apply permissions;
      # - zfs allow <receiver-user> create,mount,receive,hold,release storage/backup/freddy
      type = "zfs_fs";
      mountpoint = null;
      options.canmount = "off";
      options.readonly = "on";
    };
  };

  services.sanoid.datasets = {
    # SEEALSO; services.sanoid.datasets@backup.nix
    # Optionally override dataset storage pattern here
    # "storage/backup/<dataset>" = {};
  };

  systemd.services."zfs-backup-permissions" = {
    description = "ZFS backup dataset permissions";
    conflicts = [ "shutdown.target" ];
    wantedBy = [ "sysinit.target" ];
    before = [
      "shutdown.target"
      "sysinit.target"
    ];
    after = [ "local-fs.target" ];
    path = [ config.boot.zfs.package ];
    enableStrictShellChecks = true;
    script = ''
      zfs allow "${config.users.users.freddy.name}" ${
        lib.concatStringsSep "," [
          "receive:append" # Requires create -> requires mount
          "create"
          "mount"
          "hold"
          "release"
        ]
      } storage/backup/freddy
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Run as root
    };
    unitConfig.DefaultDependencies = false;
  };

  environment.systemPackages = [
    # NOTE; Software used by sending syncoid
    pkgs.lzop
    pkgs.mbuffer
  ];
}
