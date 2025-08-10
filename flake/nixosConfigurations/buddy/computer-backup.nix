{
  lib,
  pkgs,
  config,
  ...
}:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "resilio-sync"
    ];

  environment.systemPackages = [ pkgs.resilio-sync ];

  sops.secrets = {
    resilio-license = {
      format = "binary";
      sopsFile = ./resilio-license.encrypted.json;
      restartUnits = [
        config.systemd.services.resilio.name
      ];
    };

    # Generate key identifiers with; head -c4 /dev/urandom | od -A none -t x4
    # Generate new keys with; rslsync --generate-secret
    sync-key-3985f5a5 = {
      owner = "rslsync";
      restartUnits = [
        config.systemd.services.resilio.name
      ];
    };
  };

  disko.devices.zpool.storage.datasets = {
    "documents/3985f5a5" = {
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = "${config.services.resilio.directoryRoot}/3985f5a5";
      # NOTE; Refquota is the property matching the intuitive thinking "how much storage space do I have".
      options.refquota = "50G";
    };
  };

  services.resilio = {
    # Use `rslsync --dump-sample-config´ to view an example configuration
    enable = true;
    checkForUpdates = false;
    licenseFile = config.sops.secrets.resilio-license.path;
    httpListenAddr = "127.69.55.1";
    httpListenPort = 9000;
    useUpnp = false;
    # ERROR; If shares are defined, the webUI must be disabled (according to the options doc)
    enableWebUI = false;
    storagePath = "/var/lib/resilio-sync";
    directoryRoot = "/var/lib/backup-roots";
    sharedFolders = [
      {
        directory = "${config.services.resilio.directoryRoot}/3985f5a5";
        knownHosts = [ ];
        searchLAN = true;
        # Use `rslsync --generate-secret` to generate a read-write key for a shared folder
        secret = {
          _secret = config.sops.secrets.sync-key-3985f5a5.path;
        };
        useDHT = true;
        useRelayServer = true;
        useSyncTrash = true;
        useTracker = true;
      }
    ];
  };

  systemd.services.resilio = {
    serviceConfig = {
      StateDirectory =
        assert config.services.resilio.directoryRoot == "/var/lib/backup-roots";
        [
          "backup-roots"
          "backup-roots/3985f5a5"
        ];
    };
  };
}
