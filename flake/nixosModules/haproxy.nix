# NOTE; Ripped from jvanbruegge's and blurgyy's nix repo
# REF; https://github.com/jvanbruegge/server-config/blob/67d46811332845ea21bc9fe8053376158af41be4/modules/haproxy.nix
# REF; https://github.com/blurgyy/flames/blob/3816474ee3a063e5d96423e07acd78a91c3b1d56/nixos/_modules/haproxy-tailored/default.nix
#
# TODO; Examples on all options!
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.proesmans.haproxy;

  noNewlines =
    s: lib.strings.concatLines (builtins.filter (s: s != "") (lib.strings.splitString "\n" s));
  indentStr =
    s: lib.strings.concatLines (builtins.map (x: "  ${x}") (lib.strings.splitString "\n" s));

  writeHaproxyConfig =
    name: text:
    pkgs.runCommandLocal name
      {
        inherit text;
        passAsFile = [ "text" ];
        nativeBuildInputs = [ cfg.package ];
      } # sh
      ''
        cp "$textPath" $out
        # ERROR; Haproxy also attempts to validate content of referenced paths (eg DH-Param file, PEM files)
        haproxy -c -f $out
      '';

  haproxyCfg =
    (if cfg.validateConfigFile then writeHaproxyConfig else pkgs.writeText) "haproxy.conf"
      (mkHAProxyConfig cfg.settings);

  # NOTE; Stanzas do not need newline separator because each mkXXXX value ends with a newline!
  mkHAProxyConfig = cfg: ''
    global
    ${indentStr (mkGlobal cfg.global)}
    ${lib.strings.concatMapAttrsStringSep "" (
      name: x: "defaults ${name}\n${indentStr (mkDefault x)}"
    ) cfg.defaults}
    ${lib.strings.concatMapAttrsStringSep "" (
      name: x: "crt-store ${name}\n${indentStr (mkCertificateStore x)}"
    ) cfg.crt-stores}
    ${lib.strings.concatMapAttrsStringSep "" (
      name: x:
      "listen ${name}${
        lib.strings.optionalString (x.defaultsFrom != null) " from ${x.defaultsFrom}"
      }\n${indentStr (mkListen x)}"
    ) cfg.listen}
    ${lib.strings.concatMapAttrsStringSep "" (
      name: x:
      "frontend ${name}${
        lib.strings.optionalString (x.defaultsFrom != null) " from ${x.defaultsFrom}"
      }\n${indentStr (mkFrontend x)}"
    ) cfg.frontend}
    ${lib.strings.concatMapAttrsStringSep "" (
      name: x:
      "backend ${name}${
        lib.strings.optionalString (x.defaultsFrom != null) " from ${x.defaultsFrom}"
      }\n${indentStr (mkBackend x)}"
    ) cfg.backend}
    ${cfg.extraConfig}
  '';

  globalModule = lib.types.submodule (
    { ... }:
    {
      options = {
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

      ${lib.optionalString (cfg.sslDhparam != null) "ssl-dh-param-file '${cfg.sslDhparam}'"}
      ${cfg.extraConfig}
    '';

  defaultsModule = lib.types.submodule (
    { ... }:
    {
      options = {
        mode = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "tcp"
              "http"
            ]
          );
          default = null;
        };

        option = lib.mkOption {
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

  timeoutModule = lib.types.submodule (
    { ... }:
    {
      options = {
        connect = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        client = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        server = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        tunnel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    }
  );

  compressionModule = lib.types.submodule (
    { ... }:
    {
      options = {
        algo = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.listOf (
              lib.types.enum [
                "gzip"
                "deflate"
              ]
            )
          );
          default = null;
        };
        type = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
        };
      };
    }
  );

  mkDefault =
    default:
    noNewlines ''
      ${lib.strings.concatMapStringsSep "\n" (opt: "option ${opt}") default.option}
      ${lib.strings.concatStringsSep "\n" (
        lib.attrsets.mapAttrsToList (name: x: "timeout ${name} ${x}") (
          lib.filterAttrs (_: v: v != null) default.timeout
        )
      )}
      ${lib.strings.concatStringsSep "\n" (
        lib.attrsets.mapAttrsToList (name: x: "compression ${name} ${builtins.concatStringsSep " " x}") (
          lib.filterAttrs (_: v: v != null) default.compression
        )
      )}
      ${default.extraConfig}
    '';

  certificateModule = lib.types.submodule (
    { ... }:
    {
      options = {
        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
      };
    }
  );

  mkCertificateStore = cfg: noNewlines cfg.extraConfig;

  bindModule = lib.types.submodule {
    options = {
      location = lib.mkOption {
        type = lib.types.str;
        example = "127.0.0.1:8500";
      };

      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      extraOptions = lib.mkOption {
        type = lib.types.separatedString " ";
        default = "";
      };
    };
  };

  mkBind =
    bind:
    if (builtins.isString bind) then
      "bind ${bind}"
    else
      "bind ${bind.location}${
        lib.strings.optionalString (bind.interface != null) " interface ${bind.interface}"
      } ${bind.extraOptions}";

  backendReferenceModule = lib.types.submodule (
    { ... }:
    {
      options = {
        name = lib.mkOption { type = lib.types.str; };
        isDefault = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        condition = lib.mkOption {
          type = lib.types.str;
          example = "if !HTTP";
        };
      };
    }
  );

  mkBackendReference =
    backend:
    if builtins.isString backend then
      "use_backend ${backend}"
    else
      ''
        ${if backend.isDefault then "default" else "use"}_backend ${backend.name}${
          lib.strings.optionalString (!backend.isDefault) " if ${backend.condition}"
        }
      '';

  frontendSpecification = {
    defaultsFrom = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    description = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    mode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "tcp"
          "http"
        ]
      );
      default = null;
    };

    bind = lib.mkOption {
      type = lib.types.listOf (
        lib.types.oneOf [
          lib.types.str
          bindModule
        ]
      );
    };

    timeout = lib.mkOption {
      type = timeoutModule;
      default = { };
    };

    option = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    acl = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    request = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    compression = lib.mkOption {
      type = compressionModule;
      default = { };
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };

    backend = lib.mkOption {
      type = lib.types.listOf (
        lib.types.oneOf [
          lib.types.str
          backendReferenceModule
        ]
      );
      default = [ ];
    };
  };

  mkFrontend =
    frontend:
    noNewlines ''
      ${lib.strings.optionalString (frontend.description != null) "description ${frontend.description}"}
      ${lib.strings.optionalString (frontend.mode != null) "mode ${frontend.mode}"}
      ${lib.strings.concatMapStringsSep "\n" mkBind frontend.bind}
      ${lib.strings.concatMapStringsSep "\n" (opt: "option ${opt}") frontend.option}
      ${lib.strings.concatMapAttrsStringSep "\n" (name: x: "timeout ${name} ${x}") (
        lib.filterAttrs (_: v: v != null) frontend.timeout
      )}
      ${lib.strings.concatMapAttrsStringSep "\n" (name: x: "acl ${name} ${x}") frontend.acl}
      ${lib.strings.concatMapStringsSep "\n" (x: "${frontend.mode}-request ${x}") frontend.request}
      ${lib.strings.concatStringsSep "\n" (
        lib.attrsets.mapAttrsToList (name: x: "compression ${name} ${builtins.concatStringsSep " " x}") (
          lib.filterAttrs (_: v: v != null) frontend.compression
        )
      )}
      ${frontend.extraConfig}
      ${lib.strings.concatMapStringsSep "\n" mkBackendReference frontend.backend}
    '';

  backendServerModule = lib.types.submodule (
    { ... }:
    {
      options = {
        location = lib.mkOption {
          type = lib.types.str;
          example = "127.0.0.1:8080";
        };

        id = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          example = 1;
          default = null;
        };

        extraOptions = lib.mkOption {
          type = lib.types.separatedString " ";
          example = "send-proxy-v2 check";
          default = "";
        };
      };
    }
  );

  mkBackendServer =
    name: server:
    if builtins.isString server then
      "server ${name} ${server}"
    else
      "server ${name} ${server.location}${
        lib.strings.optionalString (server.id != null) " id ${server.id}"
      } ${server.extraOptions}";

  backendSpecification = {
    defaultsFrom = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    description = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    mode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "tcp"
          "http"
        ]
      );
      default = null;
    };

    timeout = lib.mkOption {
      type = timeoutModule;
      default = { };
    };

    option = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    acl = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    request = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    balance = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "roundrobin"
          "leastconn"
          "source"
          "first"
        ]
      );
      default = null;
      example = "roundrobin";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };

    server = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.str
          backendServerModule
        ]
      );
      default = { };
    };
  };

  mkBackend =
    backend:
    noNewlines ''
      ${lib.strings.optionalString (backend.description != null) "description ${backend.description}"}
      ${lib.strings.optionalString (backend.mode != null) "mode ${backend.mode}"}
      ${lib.strings.concatMapStringsSep "\n" (opt: "option ${opt}") backend.option}
      ${lib.strings.concatMapAttrsStringSep "\n" (name: x: "acl ${name} ${x}") backend.acl}
      ${lib.strings.concatMapStringsSep "\n" (x: "${backend.mode}-request ${x}") backend.request}
      ${lib.strings.concatMapAttrsStringSep "\n" (name: x: "timeout ${name} ${x}") (
        lib.filterAttrs (_: v: v != null) backend.timeout
      )}
      ${lib.strings.optionalString (backend.balance != null) "balance ${backend.balance}"}
      ${backend.extraConfig}
      ${lib.strings.concatMapAttrsStringSep "\n" mkBackendServer backend.server}
    '';

  mkListen =
    listen:
    noNewlines ''
      ${lib.strings.optionalString (listen.mode != null) "mode ${listen.mode}"}
      ${lib.strings.concatMapStringsSep "\n" mkBind listen.bind}
      ${lib.strings.concatMapStringsSep "\n" (opt: "option ${opt}") listen.option}
      ${lib.strings.concatMapAttrsStringSep "\n" (name: x: "acl ${name} ${x}") listen.acl}
      ${lib.strings.concatMapStringsSep "\n" (x: "${listen.mode}-request ${x}") listen.request}
      ${listen.extraConfig}
      ${lib.strings.concatMapStringsSep "\n" mkBackendReference listen.backend}
      ${lib.strings.concatMapAttrsStringSep "\n" mkBackendServer listen.server}
    '';
in

{
  # disabledModules = [ "${modulesPath}/services/networking/haproxy.nix" ];

  options = {
    services.proesmans.haproxy = {
      enable = lib.mkEnableOption "HAProxy, the reliable, high performance TCP/HTTP load balancer.";
      validateConfigFile = lib.mkEnableOption "validation of the configuration file at build time";

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

      settings = {
        # recommendedTimeoutSettings = lib.mkEnableOption "recommended timeout configuration";
        recommendedTlsSettings = lib.mkEnableOption "recommended ssl configuration";
        # recommendedCompressionSettings = lib.mkEnableOption "recommended compression configuration";
        # recommendedProxySettings = lib.mkEnableOption "recommended proxy configuration";

        global = lib.mkOption {
          type = globalModule;
        };

        defaults = lib.mkOption {
          type = lib.types.attrsOf defaultsModule;
          default = { };
        };

        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };

        crt-stores = lib.mkOption {
          type = lib.types.attrsOf certificateModule;
        };

        listen = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule { options = frontendSpecification // backendSpecification; }
          );
          default = { };
        };

        frontend = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule { options = frontendSpecification; });
          default = { };
        };

        backend = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule { options = backendSpecification; });
          default = { };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # configuration file indirection is needed to support reloading
    environment.etc."haproxy.cfg".source = haproxyCfg;

    services.proesmans.haproxy.settings = {
      global.extraConfig = lib.mkIf cfg.settings.recommendedTlsSettings ''
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
      '';
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
        SystemCallFilter = [
          "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync"
        ];
        AmbientCapabilities = [
          "CAP_NET_BIND_SERVICE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_BIND_SERVICE"
        ];
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
