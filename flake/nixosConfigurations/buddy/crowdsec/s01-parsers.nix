[
  {
    name = "bertp/immich-logs";
    description = "Parse Immich logs";
    # debug = true; # DEBUG
    filter = "evt.Parsed.program == 'immich'";
    onsuccess = "next_stage";
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
  {
    name = "bertp/kanidm-logs";
    description = "Detect authentication errors in kanidm logs";
    # debug = true; # DEBUG
    filter = "evt.Parsed.program == 'kanidm'";
    onsuccess = "next_stage";
    nodes = [
      {
        grok = {
          # f4e820f0-ecca-456d-b861-77dd9eb51d34 INFO     ┝━ ｉ [info]:  | connection_addr: 127.0.0.1:42288 | client_ip_addr: 192.168.88.245
          pattern = ".*%{UUID:request_id}.*client_ip_addr: %{IP:client_ip}.*";
          apply_on = "message";
          statics = [
            {
              meta = "log_type";
              value = "kanidm_requestinfo";
            }
          ];
        };
        stash = [
          {
            # Kanidm logs in multiline, so the client IP must be stored to retrieve at the next log line (if error)
            name = "request_ip_association";
            key = "evt.Parsed.request_id";
            value = "evt.Parsed.client_ip";
            # LRU cache, only size matters which correlates to approximate maximum requests per second, to match log lines which are
            # always printed next to each other!
            ttl = "15s";
            size = 1500; # 100 requests/second
            strategy = "LRU";
          }
        ];
      }
      {
        # NOTE; This can be improved with a new leaf node and individual matches for each error. Some errors have more "matchable" logs
        # like Result:Denied / Credentials denied + reason eg,
        # sep 14 17:23:58 buddy kanidmd[20067]: b5ce2e96-62ad-4ec2-a864-b360e2b78f14 ERROR       ┝━ 🚨 [error]: Handler::PasswordMfa -> Result::Denied - TOTP OK, password Fail | event_tag_id: 12
        # sep 14 17:23:58 buddy kanidmd[20067]: b5ce2e96-62ad-4ec2-a864-b360e2b78f14 INFO        ┝━ ｉ [info]: Credentials denied | event_tag_id: 10 | reason: incorrect password
        grok = {
          # sep 14 17:21:38 buddy kanidmd[20067]: feff248f-d5db-4e95-98f1-29704fe3ab83 ERROR       ┕━ 🚨 [error]: Invalid identity: NotAuthenticated
          # sep 14 17:21:35 buddy kanidmd[20067]: aec56dd0-2822-4596-a517-3c304f180f5a ERROR       ┝━ 🚨 [error]: Handler::PasswordMfa -> Result::Denied - TOTP Fail, password - | event_tag_id: 12
          # sep 14 17:23:48 buddy kanidmd[20067]: c77dcf4b-551b-471f-8dfc-427cbb1283f6 ERROR       ┝━ 🚨 [error]: Handler::PasswordMfa -> Result::Denied - TOTP OK, password Fail | event_tag_id: 12
          # sep 14 17:45:14 buddy kanidmd[20067]: fef41919-6c1c-4e45-af34-23442fdeec9d ERROR       ┕━ 🚨 [error]: Invalid identity: NotAuthenticated
          # sep 14 17:45:08 buddy kanidmd[20067]: f4e820f0-ecca-456d-b861-77dd9eb51d34 ERROR       ┝━ 🚨 [error]: Invalid Session State (no present session uuid) | event_tag_id: 1
          #
          # ERROR; Escaping parenthesis requires escaping the backslash! (Double escape required into the yaml file)
          pattern = ".*%{UUID:request_id}.*(Invalid identity|Err\\(NoMatchingEntries\\)|TOTP Fail|password Fail|AuthenticationDenied|Invalid Session State).*";
          apply_on = "message";
          statics = [
            {
              meta = "log_type";
              value = "kanidm_authfail";
            }
            {
              # DO NOT CHANGE; "source_ip" is common meta name!
              meta = "source_ip";
              expression = "GetFromStash(\"request_ip_association\", evt.Parsed.request_id)";
            }
          ];
        };
      }
    ];
    statics = [ ];
  }
]
