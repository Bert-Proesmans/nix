# NOTE; Ripped from jvanbruegge's and blurgyy's nix repo
# REF; https://github.com/jvanbruegge/server-config/blob/67d46811332845ea21bc9fe8053376158af41be4/modules/haproxy.nix
# REF; https://github.com/blurgyy/flames/blob/3816474ee3a063e5d96423e07acd78a91c3b1d56/nixos/_modules/haproxy-tailored/default.nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.services.haproxy;

  noNewlines =
    s: lib.strings.concatLines (builtins.filter (s: s != "") (lib.strings.splitString "\n" s));
  indentStr =
    s: lib.strings.concatLines (builtins.map (x: "  ${x}") (lib.strings.splitString "\n" s));

  haproxyCfg = pkgs.writeText "haproxy.conf" (mkHAProxyConfig cfg.settings);

  mkHAProxyConfig = cfg: ''
    global
    ${indentStr (mkGlobal cfg.settings.global)}
      
    defaults
    ${indentStr (mkGlobal cfg.settings.defaults)}

    ${lib.strings.concatStrings (
      lib.attrsets.mapAttrsToList (name: x: "frontend ${name}\n${indentStr (mkFrontend x)}") cfg.frontends
    )}
    ${lib.strings.concatStrings (
      lib.attrsets.mapAttrsToList (name: x: "backend ${name}\n${indentStr (mkBackend x)}") cfg.backends
    )}
    ${cfg.extraConfig}
  '';

  globalModule = lib.types.submodule (
    { ... }:
    {
      options = {
        recommendedTlsSettings = lib.mkEnableOption "recommended ssl configuration";
        sslDhparam = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/path/to/dhparams.pem";
          description = "Path to DH parameters file.";
        };
        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
      };
    }
  );

  mkGlobal =
    cfg:
    noNewlines ''
      # needed for hot-reload to work without dropping packets in multi-worker mode
      stats socket /run/haproxy/haproxy.sock mode 600 expose-fd listeners level user

      log stdout format raw local0 info

      ${lib.optionalString cfg.recommendedTlsSettings ''
        # generated 2025-08-15, Mozilla Guideline v5.7, HAProxy 3.2, OpenSSL 3.4.0, intermediate config
        # https://ssl-config.mozilla.org/#server=haproxy&version=3.2&config=intermediate&openssl=3.4.0&guideline=5.7
        #
        ssl-default-bind-curves X25519:prime256v1:secp384r1
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options prefer-client-ciphers ssl-min-ver TLSv1.2 no-tls-tickets
        ssl-default-server-curves X25519:prime256v1:secp384r1
        ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305
        ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-server-options ssl-min-ver TLSv1.2 no-tls-tickets
      ''}

      ${lib.optionalString cfg.sslDhparam != null "ssl-dh-param-file '${cfg.sslDhparam}'"}

      ${cfg.extraConfig}
    '';

  defaultsModule = lib.types.submodule (
    { ... }:
    {
      options = {
        inherit mode;

        options = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };

        timeout = lib.mkOption {
          type = timeoutModule;
          default = { };
        };

        compression = lib.mkOption {
          type = compressionModule;
          default = { };
        };

        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
      };
    }
  );

  mode = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "tcp"
        "http"
      ]
    );
    default = null;
  };
  timeoutModule = lib.types.submodule (
    { ... }:
    {
      options = {
        connect = lib.mkOption {
          type = lib.types.str;
          default = "5s";
        };
        client = lib.mkOption {
          type = lib.types.str;
          default = "65s";
        };
        server = lib.mkOption {
          type = lib.types.str;
          default = "65s";
        };
        tunnel = lib.mkOption {
          type = lib.types.str;
          default = "1h";
        };
      };
    }
  );
  compressionModule = lib.types.submodule {
    {...}: {
      options = {
        algo = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.enum ["gzip" "deflate"]));
          default = null;
        };
        type = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
        };
      };
    }
  };

  mkDefault =
    cfg:
    noNewlines ''
      log global

      ${concatStringsSep "\n  " (map (opt: "option ${opt}") (cfg.options))}

      ${lib.strings.concatStrings (
        lib.attrsets.mapAttrsToList (name: x: "timeout ${name} ${x}") (lib.filterAttrs (_: v: v != null) cfg.timeout)
      )}

      ${lib.strings.concatStrings (
        lib.attrsets.mapAttrsToList (name: x: "compression ${name} ${builtins.concatStringsSep " " x}") (lib.filterAttrs (_: v: v != null) cfg.compression)
      )}
    '';

  mkFrontend =
    cfg:
    noNewlines ''
      mode ${cfg.mode}
      bind ${cfg.bind.address}:${builtins.toString cfg.bind.port}${
        lib.strings.optionalString (cfg.bind.interface != null) " interface ${cfg.bind.interface}"
      } ${cfg.bind.extraOptions}
      ${lib.strings.concatLines (lib.attrsets.mapAttrsToList (name: x: "acl ${name} ${x}") cfg.acls)}
      ${lib.strings.concatMapStringsSep "\n" (x: "http-request ${x}") cfg.httpRequest}
      ${cfg.extraConfig}
      ${lib.strings.concatMapStringsSep "\n" (x: "use_backend ${x}") cfg.useBackend}
      ${lib.strings.optionalString (cfg.defaultBackend != null) "default_backend ${cfg.defaultBackend}"}
    '';

  mkBackend =
    cfg:
    noNewlines ''
      mode ${cfg.mode}
      ${lib.strings.optionalString (cfg.timeout.client != null) "timeout client ${cfg.timeout.client}"}
      ${lib.strings.optionalString (cfg.timeout.server != null) "timeout server ${cfg.timeout.server}"}
      ${lib.strings.optionalString (cfg.timeout.connect != null) "timeout connect ${cfg.timeout.connect}"}
      ${lib.strings.concatMapStringsSep "\n" (x: "server ${x}") cfg.servers}
    '';
in

{
  disabledModules = [ "${modulesPath}/services/networking/haproxy.nix" ];

  options = {
    services.haproxy = {
      enable = lib.mkEnableOption "HAProxy, the reliable, high performance TCP/HTTP load balancer.";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.haproxy;
        defaultText = lib.literalExpression "pkgs.haproxy";
        description = "HAProxy package to use.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "haproxy";
        description = "User account under which haproxy runs.";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "haproxy";
        description = "Group account under which haproxy runs.";
      };

      settings = lib.mkOption {
        type = lib.types.submodule {
          options = {
            global = lib.mkOption {
              type = globalModule;
              default = { };
            };

            defaults = lib.mkOption {
              type = defaultsModule;
              default = { };
            };

            extraConfig = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };

            # domain = mkOption {
            #   type = types.str;
            #   default = domain;
            # };

            # extraDomains = mkOption {
            #   type = types.listOf types.str;
            #   default = [ ];
            # };

            # defaultFrontends = mkOption {
            #   type = types.bool;
            #   default = true;
            # };

            frontends = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    mode = mkOption {
                      type = types.enum [
                        "http"
                        "tcp"
                      ];
                      default = "http";
                    };

                    bind = mkOption {
                      type = types.submodule {
                        options = {
                          address = mkOption {
                            type = types.str;
                            default = "";
                          };

                          port = mkOption {
                            type = types.port;
                          };

                          interface = mkOption {
                            type = types.nullOr types.str;
                            default = null;
                          };

                          extraOptions = mkOption {
                            type = types.separatedString " ";
                            default = "";
                          };
                        };
                      };
                    };

                    acls = mkOption {
                      type = types.attrsOf types.str;
                      default = { };
                    };

                    httpRequest = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };

                    useBackend = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };

                    defaultBackend = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };

                    extraConfig = mkOption {
                      type = types.lines;
                      default = "";
                    };
                  };
                }
              );
            };

            backends = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    mode = mkOption {
                      type = types.enum [
                        "http"
                        "tcp"
                      ];
                      default = "http";
                    };

                    timeout = timeoutModule;
                    default = { };

                    servers = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };
                  };
                }
              );
            };
          };
        };
      };
    };

    # ingress = mkOption {
    #   type = types.attrsOf (
    #     types.submodule {
    #       options = {
    #         subdomain = mkOption { type = types.str; };
    #         letsencrypt = mkOption {
    #           type = types.bool;
    #           default = true;
    #           description = "Enable automatic TLS certificates with letsencrypt";
    #         };
    #         address = mkOption {
    #           type = types.str;
    #           default = "127.0.0.1";
    #           description = "Address of service to proxy to";
    #         };
    #         port = mkOption {
    #           type = types.port;
    #           default = 8080;
    #           description = "Port of the service to proxy to";
    #         };
    #         proxyProtocol = mkOption {
    #           type = types.bool;
    #           default = false;
    #           description = "Send proxy protocol";
    #         };
    #       };
    #     }
    #   );
    #   default = { };
    #   description = "Configure the reverse proxy to forward requests for a given domain";
    # };
  };

  config = mkIf cfg.enable {
    # configuration file indirection is needed to support reloading
    environment.etc."haproxy.cfg".source = haproxyCfg;

    services.haproxy.settings = {
      frontends = mkIf cfg.settings.defaultFrontends {
        # https = {
        #   bind = {
        #     address = "*";
        #     port = 443;
        #     extraOptions = "ssl crt /etc/letsencrypt/live/${cfg.settings.domain}/fullchain.pem";
        #   };
        #   httpRequest = [ "set-header X-Forwarded-Proto https" ];
        #   useBackend = lib.attrsets.mapAttrsToList (
        #     name: x: "${name} if { hdr(host) -i ${x.subdomain}.${cfg.settings.domain} }"
        #   ) config.ingress;
        # };

        # http = mkIf cfg.letsencrypt {
        #   bind = {
        #     address = "*";
        #     port = 80;
        #   };
        #   acls.letsencrypt = "path_beg /.well-known/acme-challenge/";
        #   httpRequest = [ "redirect scheme https code 301 unless letsencrypt" ];
        #   useBackend = [ "certbot if letsencrypt" ];
        # };
      };

      # backends =
      #   builtins.mapAttrs (name: x: {
      #     servers = [
      #       "${name} ${x.address}:${builtins.toString x.port}${lib.optionalString x.proxyProtocol " send-proxy-v2"}"
      #     ];
      #   }) config.ingress
      #   // lib.attrsets.optionalAttrs cfg.letsencrypt {
      #     certbot.servers = [ "certbot 127.0.0.1:8403" ];
      #   };
    };

    systemd.services.haproxy = {
      description = "HAProxy";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStartPre = [
          # when the master process receives USR2, it reloads itself using exec(argv[0]), so we create a symlink there and update it before reloading
          "${pkgs.coreutils}/bin/ln -sf ${lib.getExe cfg.package} /run/haproxy/haproxy"
          # when running the config test, don't be quiet so we can see what goes wrong
          "/run/haproxy/haproxy -c -f ${haproxyCfg}"
        ];
        ExecStart = "/run/haproxy/haproxy -Ws -f /etc/haproxy.cfg -p /run/haproxy/haproxy.pid";
        ExecReload = [
          "${lib.getExe cfg.package} -c -f ${haproxyCfg}"
          "${pkgs.coreutils}/bin/ln -sf ${lib.getExe cfg.package} /run/haproxy/haproxy"
          "${pkgs.coreutils}/bin/kill -USR2 $MAINPID"
        ];
        KillMode = "mixed";
        SuccessExitStatus = "143";
        Restart = "always";
        RestartSec = 30;
        RuntimeDirectory = "haproxy";
        User = cfg.user;
        Group = cfg.group;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter = "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        # needed in case we bind to port < 1024
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };
    };

    users.users = lib.optionalAttrs (cfg.user == "haproxy") {
      haproxy = {
        group = cfg.group;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "haproxy") {
      haproxy = { };
    };
  };
}
