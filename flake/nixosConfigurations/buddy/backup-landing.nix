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
    # WARN; Sanoid calculates retention _per bucket_! Combined with receiving only the most recent snapshot, of type frequently,
    # when syncoid is configured with '--no-stream' => There are no hourly/daily/weekly/monthly snapshots sent to the backup target.
    # IF we want to persist older and less frequent snapshots we have to configure this ourselves.
    # ERROR; Generating new snapshots on target makes source and target desync on replication (snapshot) base! You generally cannot
    # touch the dataset/snapshots on target or you break replication!
    #
    # HINT; Make sure that source sends the incremental snapshot stream and that it has at least one snapshot of each interval type
    # worth for longer retention (week/day/month).
    #
    # SEEALSO; services.sanoid.datasets@backup.nix
    "storage/backup" = {
      autoprune = true;
      autosnap = false; # see WARN above
      monitor = false;

      # Define what to keep.
      # NOTE; Backup targets either receive all snapshots or only the most recent (of type frequently)
      frequently = 1; # the most recent, landed by syncoid with hold
      hourly = 0; # none
      daily = 14; # 2 weeks @ 1day rate => locally snapshotted
      monthly = 3; # 3 months @ 1month rate => locally snapshotted
      yearly = 0; # none
    };
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
    # Figure out what the hell my zpool is doing
    pkgs.zpool-iostat-viz
    (pkgs.writeShellScriptBin "check-capacity" ''
      echo "HINT; Verify capacity (CAP) is below 90%"
      zpool list
    '')
    (pkgs.writeShellScriptBin "check-amplification" ''
      echo "HINT; High operation (IOPS) count while bandwidth (mbps) remains low implies amplification!"
      sleep 2
      # (V)erbose + (y)Surpress boot statistics
      watch -n 1 "zpool iostat -vy"
    '')
  ];
}
