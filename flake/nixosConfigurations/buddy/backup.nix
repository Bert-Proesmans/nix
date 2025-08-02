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

    datasets = {
      "storage" = {
        recursive = true; # NOT ATOMIC
        process_children_only = true;

        use_template = [ "default" ];
      };

      # Less important so lower retention
      "storage/cache" = {
        use_template = [ "default" ];
        daily = 1; # 1 day @ 1 day rate
      };

      # Less important so lower retention
      "storage/log" = {
        use_template = [ "default" ];
        daily = 1; # 1 day @ 1 day rate
      };

      # NOTE; Full atomic snapshot for instant recovery
      "storage/postgres" = {
        recursive = "zfs"; # ATOMIC

        use_template = [ "default" ];
        frequent_period = 15; # Once every 15 mins
        frequently = 192; # 2 days @ 15 mins rate
        hourly = 168; # 7 days @ 1 hour rate
        daily = 90; # 3 months @ 1 day rate
        # No week/month capture
      };

      # NOTE; Full atomic snapshot for instant recovery
      "storage/sqlite" = {
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
