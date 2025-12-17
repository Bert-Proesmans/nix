{ ... }:
{
  services.sanoid =
    let
      default-settings = {
        autosnap = true;
        autoprune = true;

        # NOTE; Assumes snapshot taken every 15minutes
        frequent_period = 15; # Once every 15 mins
        frequently = 0; # none
        hourly = 0; # none
        daily = 30; # 30 days @ 1 day rate
        weekly = 0; # none
        monthly = 0; # none
        yearly = 0; # none
      };

      ignore-settings = {
        # NOTE; Use this to ignore an instantiated child dataset.
        # Instantiated (child) datasets exist when the parent dataset is configured with `recursive = true;`, aka
        # non-atomic recursive handling.
        autosnap = false;
        autoprune = false;
        monitor = false;
      };

      prune-backup-settings = {
        # NOTE; Let sanoid manage snapshots backuped from other systems
        autoprune = true;
        autosnap = false;
        monitor = false;

        # Define what to keep. This config is logically AND'ed to the snapshot schedule on the SOURCE host
        frequently = 0; # none
        hourly = 36; # 1.5 days @ 1 hour rate
        daily = 30; # 30 days @ 1 day rate
        monthly = 6; # 6 months @ 1 month rate
        yearly = 0; # none
      };
    in
    {
      enable = true;
      interval = "*:00/15:00 UTC";

      datasets = {
        "zroot/maintenance" = ignore-settings // { };

        "zroot/encryptionroot" = default-settings // {
          # NOTE; Make sure to catch all datasets.
          #
          # WARN; Datasets with non-atomic settings could have a slight offset between point in time when backups are taken.
          # This is because sanoid executes the operations outside of zfs, possibly across multiple zfs transactions.
          recursive = true; # NOT ATOMIC
          process_children_only = true;
        };

        "zroot/encryptionroot/log" = default-settings // {
          # NOTE; Less important so lower retention
          recursive = "zfs"; # ATOMIC

          daily = 7; # 7 days @ 1 day rate
        };

        "zroot/encryptionroot/postgres" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequent_period = 15; # Once every 15 mins
          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 90; # 3 months @ 1 day rate
          # No week/month capture
        };

        "zroot/encryptionroot/mysql" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequent_period = 15; # Once every 15 mins
          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 90; # 3 months @ 1 day rate
          # No week/month capture
        };

        "zroot/encryptionroot/sqlite" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequent_period = 15; # Once every 15 mins
          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 90; # 3 months @ 1 day rate
          # No week/month capture
        };

      };
    };

  systemd.services.sanoid.environment.TZ = "UTC";

  # NOTE; Have to revisit syncoid later because the nixos module is currently a mess!
  # Would be great to have send:raw here (coming in ZFS 2.4)
  # REF; https://github.com/openzfs/zfs/issues/13099#issuecomment-3356148201

  # WARN; Backups are pulled by host buddy!
  # users.users.syncoid.openssh.authorizedKeys.keyFiles = [
  #   # allow buddy to ssh
  #   "<TODO>"
  # ];

  # services.syncoid = {
  #   enable = true;
  #   interval = "00/1:00:00 UTC";

  #   commands."encryptionkey" = {
  #     source = "zroot/encryptionroot";
  #     target = "syncoid@buddy:<TODO>/freddy/encryptionroot";
  #     extraArgs = [
  #       "--no-sync-snap"
  #     ];
  #   };
  # };
}
