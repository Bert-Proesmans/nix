{
  lib,
  utils,
  pkgs,
  modulesPath,
  config,
  ...
}:

with lib;

let
  cfg = config.services.resilio;

  runConfigPath = "/run/rslsync/config.json";
  settingsFormat = pkgs.formats.json { };
  # Replaces all instances of { _secret = "<path>" } with the file contents.
  # WARN; Run the generator at preStart!
  settingsFileGenerator = pkgs.writeShellScriptBin "create-resilio-config" (
    utils.genJqSecretsReplacementSnippet runtimeSettings runConfigPath
  );

  runtimeSettings = {
    device_name = cfg.deviceName;
    storage_path = cfg.storagePath;
    listening_port = cfg.listeningPort;
    use_gui = false;
    check_for_updates = cfg.checkForUpdates;
    use_upnp = cfg.useUpnp;
    download_limit = cfg.downloadLimit;
    upload_limit = cfg.uploadLimit;
    lan_encrypt_data = cfg.encryptLAN;
  }
  // optionalAttrs (cfg.directoryRoot != "") { directory_root = cfg.directoryRoot; }
  // optionalAttrs cfg.enableWebUI {
    webui = {
      listen = "${cfg.httpListenAddr}:${toString cfg.httpListenPort}";
    }
    // (optionalAttrs (cfg.httpLogin != "") { login = cfg.httpLogin; })
    // (optionalAttrs (cfg.httpPass != "") { password = cfg.httpPass; })
    // (optionalAttrs (cfg.apiKey != "") { api_key = cfg.apiKey; });
  }
  // optionalAttrs (cfg.sharedFolders != [ ]) {
    shared_folders = (
      map (entry: {
        dir = entry.directory;
        secret = entry.secret;

        use_relay_server = entry.useRelayServer;
        use_tracker = entry.useTracker;
        use_dht = entry.useDHT;

        search_lan = entry.searchLAN;
        use_sync_trash = entry.useSyncTrash;
        known_hosts = entry.knownHosts;
      }) cfg.sharedFolders
    );
  };
in
{
  disabledModules = [
    # Upstream configuration is replaced by this file
    "${modulesPath}/services/networking/resilio.nix"
  ];

  options = {
    services.resilio = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If enabled, start the Resilio Sync daemon. Once enabled, you can
          interact with the service through the Web UI, or configure it in your
          NixOS configuration.
        '';
      };

      package = mkPackageOption pkgs "resilio-sync" { };

      deviceName = mkOption {
        type = types.str;
        example = "Voltron";
        default = config.networking.hostName;
        defaultText = literalExpression "config.networking.hostName";
        description = ''
          Name of the Resilio Sync device.
        '';
      };

      listeningPort = mkOption {
        type = types.int;
        default = 0;
        example = 44444;
        description = ''
          Listening port. Defaults to 0 which randomizes the port.
        '';
      };

      checkForUpdates = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Determines whether to check for updates and alert the user
          about them in the UI.
        '';
      };

      useUpnp = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Use Universal Plug-n-Play (UPnP)
        '';
      };

      downloadLimit = mkOption {
        type = types.int;
        default = 0;
        example = 1024;
        description = ''
          Download speed limit. 0 is unlimited (default).
        '';
      };

      uploadLimit = mkOption {
        type = types.int;
        default = 0;
        example = 1024;
        description = ''
          Upload speed limit. 0 is unlimited (default).
        '';
      };

      httpListenAddr = mkOption {
        type = types.str;
        default = "[::1]";
        example = "0.0.0.0";
        description = ''
          HTTP address to bind to.
        '';
      };

      httpListenPort = mkOption {
        type = types.int;
        default = 9000;
        description = ''
          HTTP port to bind on.
        '';
      };

      httpLogin = mkOption {
        type = types.str;
        example = "allyourbase";
        default = "";
        description = ''
          HTTP web login username.
        '';
      };

      httpPass = mkOption {
        type = types.str;
        example = "arebelongtous";
        default = "";
        description = ''
          HTTP web login password.
        '';
      };

      encryptLAN = mkOption {
        type = types.bool;
        default = true;
        description = "Encrypt LAN data.";
      };

      enableWebUI = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable Web UI for administration. Bound to the specified
          `httpListenAddress` and
          `httpListenPort`.
        '';
      };

      licenseFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        description = ''
          The file containing your resilio license key.
        '';
        example = "/var/secrets/license.btskey";
        default = null;
      };

      storagePath = mkOption {
        type = types.path;
        default = "/var/lib/resilio-sync/";
        description = ''
          Where BitTorrent Sync will store it's database files (containing
          things like username info and licenses). Generally, you should not
          need to ever change this.
        '';
      };

      apiKey = mkOption {
        type = types.str;
        default = "";
        description = "API key, which enables the developer API.";
      };

      directoryRoot = mkOption {
        type = types.str;
        default = "";
        example = "/media";
        description = "Default directory to add folders in the web UI.";
      };

      sharedFolders = mkOption {
        default = [ ];
        type = types.listOf (types.attrsOf types.anything);
        example = [
          {
            secret = {
              _secret = "/run/resilio-secret";
            };
            directory = "/home/user/sync_test";
            useRelayServer = true;
            useTracker = true;
            useDHT = false;
            searchLAN = true;
            useSyncTrash = true;
            knownHosts = [
              "192.168.1.2:4444"
              "192.168.1.3:4444"
            ];
          }
        ];
        description = ''
          Shared folder list. If enabled, web UI must be
          disabled. Secrets can be generated using `rslsync --generate-secret`.

          If you would like to be able to modify the contents of this
          directories, it is recommended that you make your user a
          member of the `rslsync` group.

          Directories in this list should be in the
          `rslsync` group, and that group must have
          write access to the directory. It is also recommended that
          `chmod g+s` is applied to the directory
          so that any sub directories created will also belong to
          the `rslsync` group. Also,
          `setfacl -d -m group:rslsync:rwx` and
          `setfacl -m group:rslsync:rwx` should also
          be applied so that the sub directories are writable by
          the group.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.deviceName != "";
        message = "Device name cannot be empty.";
      }
      {
        assertion = cfg.enableWebUI -> cfg.sharedFolders == [ ];
        message = "If using shared folders, the web UI cannot be enabled.";
      }
      {
        assertion = cfg.apiKey != "" -> cfg.enableWebUI;
        message = "If you're using an API key, you must enable the web server.";
      }
    ];

    users.users.rslsync = {
      description = "Resilio Sync Service user";
      home = cfg.storagePath;
      createHome = true;
      uid = config.ids.uids.rslsync;
      group = "rslsync";
    };

    users.groups.rslsync.gid = config.ids.gids.rslsync;

    systemd.services.resilio = {
      description = "Resilio Sync Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      restartTriggers = [ settingsFileGenerator ];

      serviceConfig = {
        Restart = "on-abort";
        UMask = "0002";
        User = "rslsync";
        RuntimeDirectory = [ "rslsync" ];

        LoadCredential =
          [ ]
          # ERROR; License filename must end with ".btskey"!
          ++ lib.optional (cfg.licenseFile != null) "LICENSE.btskey:${cfg.licenseFile}";
        ExecStartPre = [
          (lib.getExe settingsFileGenerator)

          "${(pkgs.writeShellScriptBin "init-license" ''
            SYNC_USER_PATH=$(find "${cfg.storagePath}" -maxdepth 1 -name ".SyncUser*" -print -quit)
            if [[ -z "$SYNC_USER_PATH" ]]; then
              echo "Bootstrapping identity"
              ${lib.getExe cfg.package} --nodaemon --storage "${cfg.storagePath}" --identity "${cfg.deviceName}"
              SYNC_USER_PATH=$(find "${cfg.storagePath}" -maxdepth 1 -name ".SyncUser*" -print -quit)
            fi

            ${lib.optionalString (cfg.licenseFile != null) ''
              SYNC_LICENSE_PATH=$(find "$SYNC_USER_PATH/licenses" -maxdepth 1 -type f -print -quit)
              if [[ -z "$SYNC_LICENSE_PATH" ]]; then
                echo "Installing license"
                ${lib.getExe cfg.package} --nodaemon --storage "${cfg.storagePath}" --license ''${CREDENTIALS_DIRECTORY}/LICENSE.btskey
              fi
            ''}
          '')}/bin/init-license"
        ];
        ExecStart = ''
          ${lib.getExe cfg.package} --nodaemon --config ${runConfigPath}
        '';
      };
    };
  };

  meta.maintainers = [ ];
}
