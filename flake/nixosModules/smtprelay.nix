{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.smtprelay;

  # WARN; iniWithGlobalSection instead of ini because "ini" cannot handle options without top-level section!
  settingsFormatIni = pkgs.formats.iniWithGlobalSection {
    listToValue = builtins.concatStringsSep " ";
  };

  smptprelay_ini = settingsFormatIni.generate "smtprelay.ini" {
    sections = { };
    globalSection = cfg.settings;
  };
  alias_ini = settingsFormatIni.generate "aliases.ini" {
    sections = { };
    globalSection = cfg.aliases_file;
  };
  allowed_users_conf = pkgs.writeText "allowed_users.config" (
    lib.concatMapAttrsStringSep "\n" (
      _: v: "${v.username} ${v.bcrypt-hash} ${v.email}"
    ) cfg.allowed_users
  );
in
{
  options.services.smtprelay = {
    enable = lib.mkEnableOption "SMTP relay/proxy server";
    package = lib.mkPackageOption pkgs "smtprelay" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "smtprelay";
      description = "User account under which smtprelay runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "smtprelay";
      description = "Group account under which smtprelay runs.";
    };

    tls.listener = lib.mkOption {
      type = lib.types.submodule {
        options = {
          certificate = lib.mkOption {
            type = lib.types.externalPath;
            description = ''
              Server certificate (chain) of the smtprelay listener for encrypted connections.

              Use this option instead of `settings.local_cert` to prevent the mentioned file from 
              being copied into the world-readable nix-store!
            '';
          };

          key = lib.mkOption {
            type = lib.types.externalPath;
            description = ''
              Secret to encrypt connections on the listening side of smtprelay.

              Use this option instead of `settings.local_key` to prevent the mentioned file from 
              being copied into the world-readable nix-store!
            '';
          };
        };
      };
      default = { };
    };

    tls.relay = lib.mkOption {
      type = lib.types.submodule {
        options = {
          certificate = lib.mkOption {
            type = lib.types.externalPath;
            description = ''
              Server certificate (chain) of the smtprelay listener for encrypted connections.

              Use this option instead of `settings.remote_certificate` to prevent the mentioned file from 
              being copied into the world-readable nix-store!
            '';
          };

          key = lib.mkOption {
            type = lib.types.externalPath;
            description = ''
              Secret to encrypt connections on the listening side of smtprelay.

              Use this option instead of `settings.remote_key` to prevent the mentioned file from 
              being copied into the world-readable nix-store!
            '';
          };
        };
      };
      default = { };
    };

    allowed_users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              username = lib.mkOption {
                type = lib.types.str;
                description = "SMTP auth username.";
              };
              bcrypt-hash = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Bcrypt hash of the password for SMTP auth.

                  ! Use securely random generated strings of sufficient length as password !

                  Create a bcrypt hash with the `htpasswd` program, eg `htpasswd -nBC12 "" | tr -d ':'`
                    - htpasswd is available in nixpkgs#apacheHttpd
                    - -n : do not update file, just output to stdout
                    - -B : use bcrypt algorithm
                    - -C12 : set bcrypt cost to 10 (default is 5, increase for more security but slower)
                    - Empty username "" because we only want the hash, not the username.
                '';
              };
              email = lib.mkOption {
                type = lib.types.separatedString ",";
                description = "Comma-separated list of of allowed \"from\" addresses.";
              };
            };
            config = {
              username = name;
            };
          }
        )
      );
      default = { };
      description = ''
        Attribute set containing combinations username, passwords and email addresses that are verified
        on incoming e-mails.

        WARNING: This is stored world-readable in the nix store. If you need to specify any secret credentials here, consider
        setting `settings.allowed_users` manually instead with a path to a file outside of the nix-store.
      '';
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf (lib.types.separatedString " ");
      default = { };
      example = {
        "fake@email.tld" = "real@email.tld";
      };
      description = ''
        Attribute set containing combinations of alias-address with resolved-addresses.
        This option automatically configures `settings.aliases_file` with an auto-generated ini file.
      '';
    };

    settings = lib.mkOption {
      description = ''
        Smtprelay configuration.
        See the [example smtprelay.ini file](https://github.com/decke/smtprelay/blob/master/smtprelay.ini")
        for the available options.
      '';
      default = { };
      type = lib.types.submodule {
        # ERROR; INI format expects all option values below toplevel attribute-set! eg mySection.myOption = [value]
        # freeformType = settingsFormatIni.type;
        freeformType = lib.types.attrsOf lib.types.str;
        options = {
          log_level = lib.mkOption {
            type = lib.types.enum [
              "panic"
              "fatal"
              "error"
              "warn"
              "info"
              "debug"
              "trace"
            ];
            default = "info";
            description = ''
              Log level.
            '';
          };

          hostname = lib.mkOption {
            default = "localhost.localdomain";
            type = lib.types.str;
            example = "example.com";
            description = ''
              Hostname for this SMTP server.
            '';
          };

          listen = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "127.0.0.1:25"
              "[::1]:25"
            ];
            example = [
              "tls://127.0.0.1:465"
              "starttls://[::1]:587"
            ];
            description = ''
              Addresses smtprelay should listen to for incoming unencrypted connections.
              STARTTLS and TLS are also supported but need a SSL certificate and key.
            '';
          };

          read_timeout = lib.mkOption {
            type = lib.types.str;
            default = "60s";
            example = "100us";
            description = ''
              Socket timeout for READ operations
              Duration string as sequence of decimal numbers,
              each with optional fraction and a unit suffix.
              Valid time units are "ns", "us", "ms", "s", "m", "h".
            '';
          };

          write_timeout = lib.mkOption {
            type = lib.types.str;
            default = "60s";
            example = "100us";
            description = ''
              Socket timeout for WRITE operations
              Duration string as sequence of decimal numbers,
              each with optional fraction and a unit suffix.
              Valid time units are "ns", "us", "ms", "s", "m", "h".
            '';
          };

          data_timeout = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            example = "100us";
            description = ''
              Socket timeout for DATA operations
              Duration string as sequence of decimal numbers,
              each with optional fraction and a unit suffix.
              Valid time units are "ns", "us", "ms", "s", "m", "h".
            '';
          };

          max_connections = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 100;
            example = 10;
            description = ''
              Max concurrent connections, use -1 to disable.
            '';
          };

          max_message_size = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 10240000;
            example = 20480000;
            description = ''
              Max message size in bytes.
            '';
          };

          max_recipients = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 100;
            example = 10;
            description = ''
              Max recipients per mail.
            '';
          };

          allowed_nets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "127.0.0.0/8"
              "::1/128"
            ];
            description = ''
              Networks that are allowed to send mails to us.
              Allows any address if given empty list.
            '';
          };

          allowed_sender = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "^(.*)@localhost.localdomain$";
            description = ''
              Regular expression for valid FROM EMail addresses.
              If set to "", then any sender is permitted.
            '';
          };

          allowed_recipients = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "^(.*)@localhost.localdomain$";
            description = ''
              Regular expression for valid TO EMail addresses.
              If set to "", then any recipient is permitted.
            '';
          };

          remotes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [
              "starttls://user:pass@smtp.gmail.com:587"
              "starttls://user:pass@smtp.mailgun.org:587"
            ];
            description = ''
              List of SMTP servers to relay the mails to.
              If not set, mails are discarded.

              Format:
                protocol://[user[:password]@][netloc][:port][/remote_sender][?param1=value1&...]
                
                protocol: smtp (unencrypted), smtps (TLS), starttls (STARTTLS)
                user: Username for authentication
                password: Password for authentication
                remote_sender: Email address to use as FROM
                params:
                  skipVerify: "true" or empty to prevent ssl verification of remote server's certificate
                  auth: "login" to use LOGIN authentication
            '';
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.optionalAttrs (cfg.user == "smtprelay") {
      smtprelay = {
        group = cfg.group;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "smtprelay") {
      smtprelay = { };
    };

    # DEBUG
    proesmans.nix.overlays = [
      (final: prev: {
        smtprelay = prev.smtprelay.overrideAttrs (oldAttrs: {
          patches = [
            ./relay-cert.patch
          ];
        });
      })
    ];

    systemd.services.smtprelay = {
      description = "SMTP relay/proxy server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      wants = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = [
          (lib.concatStringsSep " " (
            [
              (lib.getExe cfg.package)
              "-config ${smptprelay_ini}"
            ]
            ++ (lib.optionals (cfg.tls.listener != { }) [
              "-local_cert ${cfg.tls.listener.certificate}"
              "-local_key ${cfg.tls.listener.key}"
            ])
            ++ (lib.optionals (cfg.tls.relay != { }) [
              "-remote_certificate ${cfg.tls.relay.certificate}"
              "-remote_key ${cfg.tls.relay.key}"
            ])
            ++ (lib.optionals (cfg.allowed_users != { }) [ "-allowed_users ${allowed_users_conf}" ])
            ++ (lib.optionals (cfg.aliases != { }) [ "-aliases_file ${alias_ini}" ])
          ))
        ];

        User = cfg.user;
        Group = cfg.group;

        # Bind standard privileged ports
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];

        # Hardening
        DeviceAllow = [ "" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        PrivateUsers = false; # incompatible with CAP_NET_BIND_SERVICE
        ProcSubset = "pid";
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        UMask = "0077";
      };
    };
  };
}
