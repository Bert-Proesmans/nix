[
  {
    description = "Parse Immich logs";
    # debug = true; # Debug
    filter = "evt.Parsed.program == 'immich'";
    onsuccess = "next_stage";
    name = "bertp/immich-logs";
    grok = {
      #[Nest] 7  - 08/02/2023, 7:34:03    WARN [AuthService] Failed login attempt for user fds@hdd.com from ip address 176.172.44.211
      # ERROR; Datetime information is not stable, skip parsing it
      pattern = ".*Failed login attempt for user %{EMAILADDRESS:username} from ip address %{IP:source_ip}.*";
      apply_on = "message";
      statics = [
        {
          meta = "log_type";
          value = "immich_failed_auth";
        }
      ];
    };
    statics = [
      {
        meta = "service";
        value = "immich";
      }
      {
        meta = "user";
        expression = "evt.Parsed.username";
      }
      {
        meta = "source_ip";
        expression = "evt.Parsed.source_ip";
      }
    ];
  }
]
