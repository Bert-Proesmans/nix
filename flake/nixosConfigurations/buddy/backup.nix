{ ... }:
{
  services.sanoid =
    let
      default-settings = {
        autosnap = true;
        autoprune = true;

        # WARN; Assumes snapshot timer fires every 15 (or at denominator of 15) minutes
        frequent_period = 15; # Once every 15 mins
        frequently = 0; # none
        hourly = 0; # none
        daily = 10; # 10 days @ 1 day
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

        # Define what to keep.
        # WARN; This config is logically AND'ed to the snapshot schedule on the SOURCE host!
        frequently = 4; # 1 hour @ 15min rate
        hourly = 0; # none
        daily = 60; # 60 days @ 1day rate
        monthly = 0; # none
        yearly = 0; # none
      };
    in
    {
      enable = true;
      interval = "*:00/15:00 UTC";

      datasets = {
        "storage" = default-settings // {
          # NOTE; Make sure to catch all datasets.
          #
          # WARN; Datasets with non-atomic settings could have a slight offset between point in time when backups are taken.
          # This is because sanoid executes the operations outside of zfs, possibly across multiple zfs transactions.
          recursive = true; # NOT ATOMIC
          process_children_only = true;
        };

        "storage/backup" = prune-backup-settings // {
          # NOTE; Maintain backup snapshots of other systems
          recursive = true; # NOT ATOMIC
          process_children_only = true;
        };

        "storage/documents" = default-settings // {
          # NOTE; Retain recent changes with high frequency, but not older changes.
          recursive = true; # NOT ATOMIC
          process_children_only = true;

          frequently = 672; # 7 days @ 15 mins rate
          hourly = 720; # 30 days @ 1 hour rate
          daily = 0; # none
          weekly = 0; # none
          monthly = 24; # 2 years @ 1 month rate
        };

        "storage/log" = default-settings // {
          # NOTE; Less important so lower retention
          recursive = "zfs"; # ATOMIC

          daily = 7; # 7 days @ 1 day rate
        };

        "storage/postgres" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 30; # 1 month @ 1 day rate
          # No week/month capture
        };

        "storage/sqlite" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 30; # 1 month @ 1 day rate
          # No week/month capture
        };

        "storage/maintenance" = ignore-settings // { };
      };
    };

  systemd.services.sanoid.environment.TZ = "UTC";

  # TODO; Actually backup these snapshots!
}
