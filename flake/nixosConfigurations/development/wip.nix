{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.caddy = {
    enable = true;
    enableReload = false;
    # ERROR; Port is not automatically cast to string-type inside configuration.
    # REF; https://github.com/NixOS/nixpkgs/pull/507283
    # httpPort = 8080;
    # httpsPort = 8443;
    globalConfig = ''
      # https://github.com/NixOS/nixpkgs/issues/389016
      admin off

      # REF; https://github.com/NixOS/nixpkgs/pull/507283
      http_port 8080
      # REF; https://github.com/NixOS/nixpkgs/pull/507283
      https_port 8443
    '';
    logFormat = ''
      level DEBUG
    '';
    virtualHosts."whoami" = {
      hostName = "me.caddy.localhost";
      extraConfig = ''
        # ERROR; whoami binds to IPv4, no ipv6 binding
        reverse_proxy 127.0.0.1:8000

        forward_auth http://[::1]:4456 {
          # NOTE; Caddy automatically sets the following headers on proxy;
          #   - X-Forwarded-Method
          #   - X-Forwarded-Proto
          #   - X-Forwarded-Host
          #   - X-Forwarded-Uri
          #
          # The headers above must be trusted by downstream services (eg Heimdall)!

          # No communication through uri customization
          # SEEALSO; automatically set headers, NOTE above
          uri          /

          # Pass header Authorization from Heimdall back to _the client_
          # SEEALSO; Heimdall contextualizers and finalizers  
          copy_headers Authorization 
        }
      '';
    };
  };

  services.whoami = {
    enable = true;
    port = 8000;
  };

  systemd.services.heimdall-proxy =
    let
      serve-port = 4456;
      management-port = 4457;
      settingsFormat = pkgs.formats.json { };
      config-file = settingsFormat.generate "heimdall.config.json" ({
        log.level = "debug";
        tracing.enabled = false;
        metrics.enabled = false;

        serve = {
          host = "[::1]";
          port = serve-port;
          trusted_proxies = [ "::1" ];
        };
        management = {
          host = "[::1]";
          port = management-port;
        };

        mechanisms = {
          authenticators = [
            {
              id = "deny_all";
              type = "unauthorized";
            }
            {
              id = "anon";
              type = "anonymous";
            }
          ];
          finalizers = [
            {
              id = "noop";
              type = "noop";
            }
          ];
        };

        default_rule = {
          execute = [
            { authenticator = "deny_all"; }
          ];
        };

        providers = {
          file_system = {
            src = rules-file;
            watch = false;
          };
        };
      });

      rules-file = settingsFormat.generate "heimdall.rules.json" ({
        version = "1alpha4"; # ??
        rules = [
          {
            id = "demo:public";
            match.methods = [ "GET" ];
            match.routes = [
              { path = "/public"; }
            ];
            execute = [
              { authenticator = "anon"; }
              { finalizer = "noop"; }
            ];
          }
        ];
      });
    in
    {
      wantedBy = [ "multi-user.target" ];

      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        User = "heimdall";
        Group = "heimdall";
        DynamicUser = true;
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe pkgs.heimdall-proxy)
          "serve"
          "decision"
          "--config"
          config-file
          "--insecure"
        ]);

        # Hardening
        AmbientCapabilities = "";
        CapabilityBoundingSet = [ "" ];
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_INET AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SocketBindAllow = [
          "tcp:${toString serve-port}"
          "tcp:${toString management-port}"
        ];
        SocketBindDeny = "any";
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
}
