{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    mkPackageOption
    mkIf
    literalExpression
    optional
    ;
  inherit (lib.types)
    submodule
    listOf
    attrsOf
    nullOr
    oneOf
    bool
    path
    str
    int
    singleLineStr
    anything
    ;

  cfg = config.services.proesmans.resilio;

  # sharedFoldersSecretFiles = map
  #   (entry: {
  #     dir = entry.directory;
  #     secretFile =
  #       if builtins.hasAttr "secret" entry then
  #         toString
  #           (
  #             pkgs.writeTextFile {
  #               name = "secret-file";
  #               text = entry.secret;
  #             }
  #           )
  #       else
  #         entry.secretFile;
  #   })
  #   cfg.sharedFolders;

  # createConfig = pkgs.writeShellScriptBin "create-resilio-config" (
  #   if cfg.sharedFolders != [ ] then
  #     ''
  #       ${pkgs.jq}/bin/jq \
  #         '.shared_folders |= map(.secret = $ARGS.named[.dir])' \
  #         ${
  #           lib.concatMapStringsSep " \\\n  " (
  #             entry: ''--arg '${entry.dir}' "$(cat '${entry.secretFile}')"''
  #           ) sharedFoldersSecretFiles
  #         } \
  #         <${configFile} \
  #         >${runConfigPath}
  #     ''
  #   else
  #     ''
  #       # no secrets, passing through config
  #       cp ${configFile} ${runConfigPath};
  #     ''
  # );

in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "deviceName" ]
      [ "services" "proesmans" "resilio" "settings" "device_name" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "storagePath" ]
      [ "services" "proesmans" "resilio" "settings" "storage_path" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "listeningPort" ]
      [ "services" "proesmans" "resilio" "settings" "listening_port" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "enableWebUI" ]
      [ "services" "proesmans" "resilio" "settings" "use_gui" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "checkForUpdates" ]
      [ "services" "proesmans" "resilio" "settings" "check_for_updates" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "useUpnp" ]
      [ "services" "proesmans" "resilio" "settings" "use_upnp" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "downloadLimit" ]
      [ "services" "proesmans" "resilio" "settings" "download_limit" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "uploadLimit" ]
      [ "services" "proesmans" "resilio" "settings" "upload_limit" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "encryptLAN" ]
      [ "services" "proesmans" "resilio" "settings" "lan_encrypt_data" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "directoryRoot" ]
      [ "services" "proesmans" "resilio" "settings" "directory_root" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "httpListenAddr" ]
      [ "services" "proesmans" "resilio" "settings" "web_ui" "listen" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "httpListenPort" ]
      [ "services" "proesmans" "resilio" "settings" "web_ui" "listen" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "httpLogin" ]
      [ "services" "proesmans" "resilio" "settings" "web_ui" "login" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "httpPass" ]
      [ "services" "proesmans" "resilio" "settings" "web_ui" "password" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "apiKey" ]
      [ "services" "proesmans" "resilio" "settings" "web_ui" "api_key" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "proesmans" "resilio" "sharedFolders" ]
      [ "services" "proesmans" "resilio" "settings" "shared_folders" ]
    )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "directory" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "dir" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "useRelayServer" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "use_relay_server" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "useTracker" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "use_tracker" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "useDHT" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "use_dht" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "searchLAN" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "search_lan" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "useSyncTrash" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "use_sync_trash" ]
    # )
    # TODO
    # (lib.mkRenamedOptionModule
    #   [ "services" "proesmans" "resilio" "sharedFolders" "" "knownHosts" ]
    #   [ "services" "proesmans" "resilio" "settings" "shared_folders" "" "known_hosts" ]
    # )
  ];

  options = {
    services.proesmans.resilio = {
      enable = mkOption {
        type = bool;
        default = false;
        description = ''
          If enabled, start the Resilio Sync daemon. Once enabled, you can
          interact with the service through the Web UI, or configure it in your
          NixOS configuration.
        '';
      };

      package = mkPackageOption pkgs "resilio-sync" { };

      user = mkOption {
        type = singleLineStr;
        default = "rslsync";
        description = ''
          User which the service runs as.
          You have to setup the user yourself if you change this value. Generally, you should not need to change this.
        '';
      };

      group = mkOption {
        type = singleLineStr;
        default = "rslsync";
        description = ''
          Group which the service runs as.
          You have to setup the group yourself if you change this value. Generally, you should not need to change this.
        '';
      };

      runtimeConfigPath = mkOption {
        type = path;
        readOnly = true;
        default = "/run/rslsync/config.json";
        description = ''
          The path where all configuration is provided from. Refer to 
          [the Resilion documentation](https://help.resilio.com/hc/en-us/articles/206178884-Running-Sync-in-configuration-mode)
          for more information.
        '';
      };

      _debug_config = mkOption {
        type = anything;
        readOnly = true;
        default = pkgs.writeText "config.json" (builtins.toJSON cfg.settings);
      };

      settings = mkOption {
        default = { };
        description = ''
          <TODO>
          Freeform configuration via environment variables for Anubis.

          See [the documentation](https://anubis.techaro.lol/docs/admin/installation) for a complete list of
          available environment variables.
        '';
        type = submodule [
          {
            freeformType = attrsOf (
              nullOr (oneOf [
                str
                int
                bool
              ])
            );

            options = {
              device_name = mkOption {
                type = str;
                example = "Voltron";
                default = config.networking.hostName;
                defaultText = literalExpression "config.networking.hostName";
                description = ''
                  Name of the device which is advertised to Resilio Sync peers.
                '';
              };

              storage_path = mkOption {
                type = path;
                default = "/var/lib/resilio-sync";
                description = ''
                  Where BitTorrent Sync will store it's database files (containing things like username info and licenses).
                  You have to setup the directory yourself if you change this value. Generally, you should not need to change this.
                '';
              };

              listening_port = mkOption {
                type = int;
                default = 0;
                example = 44444;
                description = ''
                  Listening port. Defaults to 0 which randomizes the port.
                '';
              };

              check_for_updates = mkOption {
                type = bool;
                default = true;
                description = ''
                  Determines whether to check for updates and alert the user
                  about them in the UI.
                '';
              };

              use_upnp = mkOption {
                type = bool;
                default = true;
                description = ''
                  Use Universal Plug-n-Play (UPnP)
                '';
              };

              download_limit = mkOption {
                type = int;
                default = 0;
                example = 1024;
                description = ''
                  Download speed limit in kB/s. 0 is unlimited (default).
                '';
              };

              upload_limit = mkOption {
                type = int;
                default = 0;
                example = 1024;
                description = ''
                  Upload speed limit in kB/s. 0 is unlimited (default).
                '';
              };

              lan_encrypt_data = mkOption {
                type = bool;
                default = true;
                description = "Encrypt LAN data.";
              };

              directory_root = mkOption {
                type = str;
                default = null;
                example = "/media";
                description = "Default directory to add folders in the web UI.";
              };

              # TODO; does this option actually do anything?
              use_gui = mkOption {
                type = bool;
                default = false;
                description = ''
                  Enable Web UI for administration. Bound to the specified
                  `httpListenAddress` and
                  `httpListenPort`.
                '';
              };

              web_ui = mkOption {
                default = null;
                description = ''<TODO>'';
                type = submodule [
                  {
                    freeformType = attrsOf (
                      nullOr (oneOf [
                        str
                        int
                        bool
                      ])
                    );

                    options = {
                      # httpListenAddr = mkOption {
                      #   type = types.str;
                      #   default = "[::1]";
                      #   example = "0.0.0.0";
                      #   description = ''
                      #     HTTP address to bind to.
                      #   '';
                      # };

                      # httpListenPort = mkOption {
                      #   type = types.int;
                      #   default = 9000;
                      #   description = ''
                      #     HTTP port to bind on.
                      #   '';
                      # };

                      login = mkOption {
                        type = str;
                        example = "allyourbase";
                        default = null;
                        description = ''
                          HTTP web login username.
                        '';
                      };

                      password_hash_unified = mkOption {
                        type = str;
                        example = "926a90d2317d16c91bac78b1e2948f32888c88add75823a7ab5fd9d2540a28d7";
                        default = null;
                        description = ''
                          HTTP web login password. This option is not recommended, use option password_hash_file to not expose the hash.
                          The value must be a hexadecimal representation of a SHA2 with 256-bit hash-digest of the password.
                          Use `echo -n "<yourpassword>" | sha256` to hash your password.
                        '';
                      };

                      password_hash_salt_unified = mkOption {
                        type = str;
                        example = "<TODO>";
                        default = null;
                        description = ''
                          Salt for the HTTP web login password.
                        '';
                      };

                      password_hash_file = mkOption {
                        type = path;
                        example = "/run/secrets/mypasswordhash";
                        default = null;
                        description = ''
                          File containing the password hash, corresponding to option password_hash_unified.
                        '';
                      };

                      dir_whitelist = mkOption {
                        type = listOf str;
                        example = "<TODO>";
                        default = null;
                        description = ''
                          Directories, relative to directory_root value, shown to the user and can be configured to sync.
                        '';
                      };

                      api_key = mkOption {
                        type = str;
                        default = null;
                        description = "API key, which enables the developer API.";
                      };
                    };
                  }
                ];
              };

              shared_folders = mkOption {
                default = [ ];
                type = listOf (attrsOf anything);
                example = [
                  {
                    # TODO
                    secretFile = "/run/resilio-secret";
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
          }
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings.device_name != "";
        message = "Device name cannot be empty.";
      }
      # TODO
      # {
      #   assertion = cfg.settings.web_ui != null -> cfg.settings.shared_folders == [ ];
      #   message = "If using shared folders, the web UI cannot be enabled.";
      # }
      # TODO
      # {
      #   assertion = cfg.apiKey != "" -> cfg.enableWebUI;
      #   message = "If you're using an API key, you must enable the web server.";
      # }
    ];

    users.users.rslsync = mkIf (cfg.user == "rslsync") {
      description = "Resilio Sync Service user";
      isSystemUser = true;
      uid = config.ids.uids.rslsync;
      group = "rslsync";
      home = cfg.storagePath; # Backwards compatibility
      createHome = true; # Backwards compatibility
    };

    users.groups.rslsync = mkIf (cfg.group == "rslsync") {
      gid = config.ids.gids.rslsync;
    };

    systemd.services.resilio = {
      description = "Resilio Sync Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Restart = "on-abort";
        UMask = "0002";
        User = cfg.user;
        RuntimeDirectory = cfg.group;
        StateDirectory = optional (cfg.settings.storage_path == "/var/lib/resilio-sync") "resilio-sync";
        ExecStartPre = [
          # "${createConfig}/bin/create-resilio-config"
        ];
        ExecStart = ''
          ${lib.getExe cfg.package} --nodaemon --config ${cfg.runtimeConfigPath}
        '';
        BindPaths = [
          "/nix/store"
          cfg.settings.storagePath
        ];
      };
    };
  };

  meta.maintainers = [ ];
}
