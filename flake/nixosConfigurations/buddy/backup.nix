{ ... }:
{
  services.sanoid = {
    enable = true;
    # WARN; At DST transition we _still_ lose one hour worth of backup due to snapshot naming collisions!
    interval = "*:00/15:00 UTC";

    templates."default" = {
      autosnap = true;
      autoprune = true;

      frequent_period = 15; # Once every 15 mins
      frequently = 0; # none
      hourly = 0; # none
      daily = 30; # 30 days @ 1 day
      weekly = 0; # none
      monthly = 0; # none
      yearly = 0; # none
    };

    templates."ignore" = {
      # NOTE; Use this to ignore an instantiated child dataset.
      # Instantiated (child) datasets exist when the parent dataset is configured with `recursive = true;`, aka
      # non-atomic recursive handling.
      autosnap = false;
      autoprune = false;
      monitor = false;
    };

    datasets = {
      "storage" = {
        # NOTE; Make sure to catch all datasets.
        #
        # WARN; Datasets with non-atomic settings could have a slight offset between point in time when backups are taken.
        # This is because sanoid executes the operations outside of zfs, possibly across multiple zfs transactions.
        recursive = true; # NOT ATOMIC
        process_children_only = true;

        use_template = [ "default" ];
      };

      "storage/documents" = {
        # NOTE; Retain recent changes with high frequency, but not older changes.
        recursive = true; # NOT ATOMIC
        process_children_only = true;

        use_template = [ "default" ];
        frequent_period = 15; # Once every 15 mins
        frequently = 672; # 7 days @ 15 mins rate
        hourly = 720; # 30 days @ 1 hour rate
        daily = 30; # 30 days @ 1 day rate
        weekly = 24; # 6 months @ 1 week rate
        monthly = 84; # 7 years @ 1 month rate
      };

      "storage/log" = {
        # NOTE; Less important so lower retention
        recursive = "zfs"; # ATOMIC

        use_template = [ "default" ];
        daily = 7; # 7 days @ 1 day rate
      };

      "storage/postgres" = {
        # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
        recursive = "zfs"; # ATOMIC

        use_template = [ "default" ];
        frequent_period = 15; # Once every 15 mins
        frequently = 192; # 2 days @ 15 mins rate
        hourly = 168; # 7 days @ 1 hour rate
        daily = 90; # 3 months @ 1 day rate
        # No week/month capture
      };

      "storage/sqlite" = {
        # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
        recursive = "zfs"; # ATOMIC

        use_template = [ "default" ];
        frequent_period = 15; # Once every 15 mins
        frequently = 192; # 2 days @ 15 mins rate
        hourly = 168; # 7 days @ 1 hour rate
        daily = 90; # 3 months @ 1 day rate
        # No week/month capture
      };
    };
  };

  # WARN; At DST transition we _still_ lose one hour worth of backup due to snapshot naming collisions!
  systemd.services.sanoid.environment.TZ = "UTC";

  # TODO; Actually backup these snapshots!
}
