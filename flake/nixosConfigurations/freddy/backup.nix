{
  lib,
  pkgs,
  utils,
  config,
  ...
}:
let
  ip-buddy = config.proesmans.facts.buddy.host.tailscale.address;
  fqdn-buddy = "buddy.internal.proesmans.eu";
in
{
  # Make sure the fqdn of buddy resolves through tailscale!
  networking.hosts."${ip-buddy}" = [ fqdn-buddy ];

  services.sanoid =
    let
      default-settings = {
        autosnap = true;
        autoprune = true;

        # WARN; Assumes snapshot timer fires every 15 (or at denominator of 15) minutes
        frequent_period = 15; # Once every 15 mins
        frequently = 0; # none
        hourly = 0; # none
        daily = 10; # 10 days @ 1 day rate
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
          # WARN; MUST HAVE a snapshot of zroot/encryptionroot since this stores the encryption volume key(s)!
          process_children_only = false;
        };

        "zroot/encryptionroot/log" = default-settings // {
          # NOTE; Less important so lower retention
          recursive = "zfs"; # ATOMIC

          daily = 7; # 7 days @ 1 day rate
        };

        "zroot/encryptionroot/postgres" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 1; # 1 for backup purposes
          # No week/month capture
        };

        "zroot/encryptionroot/mysql" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 1; # 1 for backup purposes
          # No week/month capture
        };

        "zroot/encryptionroot/sqlite" = default-settings // {
          # NOTE; Full atomic snapshot for instant recovery, must include write-ahead-log (WAL) files!
          recursive = "zfs"; # ATOMIC

          frequently = 192; # 2 days @ 15 mins rate
          hourly = 168; # 7 days @ 1 hour rate
          daily = 1; # 1 for backup purposes
          # No week/month capture
        };

      };
    };

  systemd.services.sanoid.environment.TZ = "UTC";

  services.syncoid = {
    enable = true;
    interval = "hourly"; # Value doesn't matter, overritten in explicit timer instance
    service = {
      # NOTE; Added to all syncoid systemd unit files
      requisite = [
        config.systemd.targets."buddy-online".name
      ];
      after = [
        config.systemd.targets."buddy-online".name
      ];
      serviceConfig = { };
    };
    localSourceAllow = [
      "bookmark" # Keep reference point at source for later diffing with target
      "hold" # Don't touch source until transfer completes
      # ERROR; zfs-send cannot send incrementals (zfs send -I <snapshot> <snapshot>) without 'send' 🤔
      "send"
      "send:raw" # REF; https://github.com/behlendorf/zfs/commit/6c4ede4026974e5e7b871b98f3652108860ea322
      "release"
    ];
    # NOTE; Target datasets are on another system
    localTargetAllow = [ ];
    # NOTE; Arguments passed to all syncoid invocations
    # HINT; All hosts create frequent local snapshots, the offsite backup should keep cherry-picked snapshots for a longer duration.
    commonArgs = [
      "--no-sync-snap" # No additional snapshot, use sanoid's snapshots
      # WARN; Each snapshot creates a (small) processing overhead while being received, causing high load on the target pool.
      # NOTE; '--no-stream' instructs zfs to _not send each individual snapshot_ but group changes into a single snapshot before sending.
      "--no-stream" # '-i' instead of '-I'
      "--create-bookmark" # Keep cheap pointer to replicated datasets
      "--use-hold" # Don't do anything to the dataset(snapshot) while transmitting
      "--no-rollback" # No permissions to maintain/recoved (bad) dataset on target
      # ERROR; Sendoptions get reset because this argument is defined twice!
      # "--sendoptions=raw" # Always send raw data
      # ERROR; Always set (double assignment) by upstream module.
      # "--no-privilege-elevation" # SSH user has necessary dataset permissions on target
      "--sshkey"
      # NOTE; '${CREDENTIALS_DIRECTORY}' passes through "escapeShellArguments"
      "\${CREDENTIALS_DIRECTORY}/sshKey"
    ];

    # WARN; Sending encrypted streams automatically sets 'encryption' and 'keylocation=prompt' properties on the destination dataset!
    # You could add '--props' (to zfs send, through --sendoptions=) to clone the source properties into target dataset, but that also
    # takes in other options like 'mountpoint' and 'canmount'..
    # WARN; Because keylocation=prompt is automatically set on the target dataset by zfs receive, zfs will ask for a loaded key on
    # the target host while attempting to mount. This operational discrepancy with the source system is confusing.
    commands = {
      "zroot/encryptionroot" = {
        # NOTE; Need encryptionroot dataset because the volume keys are stored here
        target = "freddy@${fqdn-buddy}:storage/backup/freddy/encryptionroot";
        # Manual selection of mirrored datasets because local data (logs, nix-store etc) is also encrypted
        recursive = false;
        # WARN; See note above.
        sendOptions = "w"; # ra(w)
        service.serviceConfig.LoadCredential = [ "sshKey:${config.sops.secrets."buddy_ssh".path}" ];
      };
      "zroot/encryptionroot/sqlite" = {
        target = "freddy@${fqdn-buddy}:storage/backup/freddy/encryptionroot/sqlite";
        recursive = true;
        # WARN; See note above.
        sendOptions = "w"; # ra(w)
        service.serviceConfig.LoadCredential = [ "sshKey:${config.sops.secrets."buddy_ssh".path}" ];
      };
      "zroot/encryptionroot/mysql" = {
        target = "freddy@${fqdn-buddy}:storage/backup/freddy/encryptionroot/mysql";
        recursive = true;
        # WARN; See note above.
        sendOptions = "w"; # ra(w)
        service.serviceConfig.LoadCredential = [ "sshKey:${config.sops.secrets."buddy_ssh".path}" ];
      };
      "zroot/encryptionroot/postgres" = {
        target = "freddy@${fqdn-buddy}:storage/backup/freddy/encryptionroot/postgres";
        recursive = true;
        # WARN; See note above.
        sendOptions = "w"; # ra(w)
        service.serviceConfig.LoadCredential = [ "sshKey:${config.sops.secrets."buddy_ssh".path}" ];
      };
    };
  };

  systemd.timers = lib.mapAttrs' (
    name: c:
    lib.nameValuePair "syncoid-${utils.escapeSystemdPath name}" ({
      timerConfig = {
        # NOTE; This timer should fire at least once every 30 minutes.
        #
        # Default interval every 15 minutes-
        OnCalendar = lib.mkForce "*:00/15:00 UTC";
        # -with a random offset of 15 minutes to smear target system load.
        #
        # WARN; 'RandomizedOffsetSec' is a better option than 'RandomizedDelaySec' because it offsets the next start time
        # persistently (across reboots) and deterministically (every unit has a uniqe delay).
        #
        # NOTE; Validate syntax using;
        # systemd-analyze timespan "<value>"
        RandomizedOffsetSec = "15 minutes";
        Persistent = true;
      };
    })
  ) config.services.syncoid.commands;

  environment.systemPackages = [
    # NOTE; Software used by sending syncoid
    pkgs.lzop
    pkgs.mbuffer
  ];
}
