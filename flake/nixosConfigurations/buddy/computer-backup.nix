{
  lib,
  pkgs,
  config,
  ...
}:
let
  backupFolders = {
    # Generate key identifiers with; head -c4 /dev/urandom | od -A none -t x4
    # Generate new RW keys with; rslsync --generate-secret

    # Bert Proesmans
    "3985f5a5".secret = config.sops.secrets.sync-key-3985f5a5.path;
    # <redacted>
    "0128d08b".secret = config.sops.secrets.sync-key-0128d08b.path;
  };
in
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

    sync-key-3985f5a5 = {
      owner = "rslsync";
      restartUnits = [
        config.systemd.services.resilio.name
      ];
    };

    sync-key-0128d08b = {
      owner = "rslsync";
      restartUnits = [
        config.systemd.services.resilio.name
      ];
    };
  };

  disko.devices.zpool.storage.datasets = lib.mapAttrs' (
    name: _value:
    (lib.nameValuePair ("documents/" + name) ({
      type = "zfs_fs";
      # WARN; To be backed up !
      options.mountpoint = "${config.services.resilio.directoryRoot}/" + name;
      # NOTE; Refquota is the property matching the intuitive thinking "how much storage space do I have".
      options.refquota = "50G";
    }))
  ) backupFolders;

  services.resilio = {
    # Use `rslsync --dump-sample-config´ to view an example configuration
    enable = true;
    # NOTE; Doesn't seem to have an effect? 🤔
    deviceName = "Alpha sync";
    checkForUpdates = false;
    licenseFile = config.sops.secrets.resilio-license.path;
    httpListenAddr = "127.69.55.1";
    httpListenPort = 9000;
    useUpnp = false;
    # ERROR; If shares are defined, the webUI must be disabled (according to the options doc)
    enableWebUI = false;
    storagePath = "/var/lib/resilio-sync";
    directoryRoot = "/var/lib/backup-roots";
    sharedFolders = lib.mapAttrsToList (name: value: {
      directory = "${config.services.resilio.directoryRoot}/" + name;
      secret._secret = value.secret;
      #
      knownHosts = [ ];
      searchLAN = true;
      useDHT = true;
      useRelayServer = true;
      useSyncTrash = true;
      useTracker = true;
    }) backupFolders;
    # extraJsonFile = "/tmp/test.json";
  };

  systemd.services.resilio = {
    serviceConfig = {
      StateDirectory =
        assert config.services.resilio.directoryRoot == "/var/lib/backup-roots";
        [
          "backup-roots"
        ]
        ++ (lib.mapAttrsToList (name: _: "backup-roots/" + name) backupFolders);
      # ERROR; Resilio requires group write permissions on the sync-directories!
      # NOTE; Includes sticky bit (GUID), octal value 2, so all created files are for sure owned by the rslsync group.
      StateDirectoryMode = "2770";
    };
  };
}
