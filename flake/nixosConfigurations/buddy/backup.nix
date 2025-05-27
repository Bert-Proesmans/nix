{ ... }: {
  services.sanoid = {
    enable = true;
    # WARN; At DST transition we _still_ lose one hour worth of backup due to snapshot naming collisions!
    interval = "*:00/1:00 UTC";

    datasets = {
      "storage" = {
        autosnap = true;
        autoprune = true;
        recursive = true; # NOT ATOMIC

        frequently = 0; # none
        hourly = 0; # none
        daily = 30; # 30 days @ 1 day
      };

      # NOTE; Full atomic snapshot for instant recovery
      "storage/postgres" = {
        autosnap = true;
        autoprune = true;
        recursive = "zfs"; # Atomic

        frequent_period = 15; # Once every 15 mins
        frequently = 192; # 2 days @ 15 mins
        hourly = 168; # 7 days @ 1 hour
        daily = 90; # 3 months @ 1 day
        # No week/month capture
      };

      # NOTE; Full atomic snapshot for instant recovery
      "storage/sqlite" = {
        autosnap = true;
        autoprune = true;
        recursive = "zfs"; # Atomic

        frequent_period = 15; # Once every 15 mins
        frequently = 192; # 2 days @ 15 mins
        hourly = 168; # 7 days @ 1 hour
        daily = 90; # 3 months @ 1 day
        # No week/month capture
      };
    };
  };

  # WARN; At DST transition we _still_ lose one hour worth of backup due to snapshot naming collisions!
  systemd.services.sanoid.environment.TZ = "UTC";

  # TODO; Actually backup these snapshots!
}
