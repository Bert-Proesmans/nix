{
  lib,
  pkgs,
  modulesPath,
  config,
  ...
}:
let
  # Settings per proxy address
  proxy-settings-unsock =
    {
      lib,
      config,
      ip-scope-parent,
      socket-directory-parent,
      ...
    }:
    {
      options = {
        match.ip = lib.mkOption {
          description = "The IP address to match and perform a redirect";
          type = lib.types.nullOr (lib.net.types.cidrv4-in ip-scope-parent);
          default = if ip-scope-parent == "127.175.0.0/32" then "127.175.0.0" else null;
        };

        match.port = lib.mkOption {
          description = "The port to match and perform a redirect";
          type = lib.types.nullOr lib.types.port;
          default = null;
        };

        to.socket.path = lib.mkOption {
          description = ''
            The socket file.

            1. If 'to.vsock.cid' and 'to.vsock.port' are not null, this path is created automatically.
            => Assumes redirection through AF_VSOCK

            2. if 'to.vsock.cid' and 'to.vsock.port' are null, you are expected to manually create the path.
            => Assumes redirection through AF_UNIX

            3. If 'match.port' is not null, a path restriction is applied because the queried socket path
            is hardcoded inside the unsock library.
            => Assumes AF_INET socket swap, into either AF_UNIX or AF_VSOCK

            4. If 'match.port' is null, no path restriction. Then see 1 or 2.

            In summary you can point your software to an IP address or a UNIX socket, then UNSOCK will rewrite
            the IP to a UNIX or VSOCK connection or the UNIX socket to a VSOCK connection.
          '';
          type = lib.types.path;
          default = "${socket-directory-parent}/${toString config.match.port}.sock";
        };

        to.vsock.cid = lib.mkOption {
          description = ''
            VSOCK host ID. Set to -1 when binding a listener!
            CONSTANTS for connecting to a VSOCK listener;
              - VMADDR_CID_HYPERVISOR = 0 (AKA deprecated) **do not use**
              - VMADDR_CID_LOCAL = 1 (AKA loopback)
              - VMADDR_CID_HOST = 2 (AKA hypervisor)

            ERROR; Binding/connecting to VMADDR_CID_LOCAL means using the loopback transport, this transport is loaded
            when the kernel module "vhost_loopback" (aka driver) is loaded.
            If the module is not loaded, connections will never complete AKA a silent "failure".
          '';
          type = lib.types.nullOr (lib.types.addCheck lib.types.int (x: x == -1 || x > 0));
          default = null;
        };

        to.vsock.port = lib.mkOption {
          description = "VSOCK Port to redirect to";
          type = lib.types.nullOr lib.types.port;
          default = null;
        };

        to.vsock.flag-to-host = lib.mkEnableOption "diverting VSOCK communications to the host (CID 2)" // {
          default = config.to.vsock.cid != -1;
        };
      };
    };
in
{
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          imports = [
            # Must include for assertions because submodule is scope-isolated
            "${modulesPath}/misc/assertions.nix"
          ];
          options.unsock = {
            # Settings per wrapped binary
            enable = lib.mkEnableOption "redirecting AF_INET into AF_UNIX/AF_VSOCK";

            package = lib.mkPackageOption pkgs "unsock" {
              extraDescription = "This is the package used to generate AF_VSOCK instruction files, if those are defined as proxies.";
            };

            tweaks.accept-convert-all = lib.mkEnableOption "provide AF_INET-like address to accept";
            tweaks.accept-convert-vsock = lib.mkEnableOption "provided AF_INET-like address to accept when socket swapped into VSOCK only";

            socket-directory = lib.mkOption {
              description = ''
                Directory where the sockets are installed.

                If this is not the default directory, you'll have to manually create one yourself with the right permissions!
              '';
              type = lib.types.path;
              default = "/run/unsock";
            };

            ip-scope = lib.mkOption {
              description = "The scope of IP addresses which are translated into sockets";
              type = lib.net.types.cidrv4;
              default = "127.175.0.0/32";
            };

            proxies = lib.mkOption {
              description = "Information about the socket redirections to perform";
              default = [ ];
              type = lib.types.listOf (
                lib.types.submodule [
                  proxy-settings-unsock
                  ({
                    _module.args.ip-scope-parent = config.unsock.ip-scope;
                    _module.args.socket-directory-parent = config.unsock.socket-directory;
                  })
                ]
              );
            };
          };

          # NOTE; This point specializes all configuration on systemd's structure of operations.
          config =
            let
              cfg = config.unsock;
              generate-vsock-config-script = pkgs.writeShellApplication {
                name = "generate-vsock-config";
                runtimeInputs = [ cfg.package ];
                text = ''
                  # Take variables from environment or overwrite them from command line
                  export UNSOCK_FILE="''${1:-UNSOCK_FILE}"
                  export UNSOCK_VSOCK_CID="''${2:-UNSOCK_VSOCK_CID}"
                  export UNSOCK_VSOCK_PORT="''${3:-UNSOCK_VSOCK_PORT}"
                  export UNSOCK_VSOCK_CONNECT_SIBLING="''${4:-UNSOCK_VSOCK_CONNECT_SIBLING}"

                  [ -e "$UNSOCK_FILE" ] && rm --force "$UNSOCK_FILE"

                  # Execute the library, creating a config file at UNSOCK_FILE with provided details
                  libunsock.so

                  chmod 0600 "$UNSOCK_FILE"
                '';
              };
            in
            {
              assertions =
                let
                  by-socket-proxies = builtins.attrValues (
                    builtins.groupBy ({ to, ... }: to.socket.path) cfg.proxies
                  );
                  by-vsock-proxies = builtins.attrValues (
                    builtins.groupBy ({ to, ... }: "${toString to.vsock.cid}-${toString to.vsock.port}") cfg.proxies
                  );
                in
                lib.optionals (cfg.enable) (
                  (lib.warnIf (builtins.any (v: builtins.length v > 1) by-socket-proxies)
                    "Unsock: service ${name}: You have multiple proxies pointing to the same socket path. This could be intentional, otherwise verify your proxy configuration."
                  )
                    (lib.warnIf (builtins.any (v: builtins.length v > 1) by-vsock-proxies)
                      "Unsock: service ${name}: You have multiple proxies pointing to the same VSOCK listener. This could be intentional, otherwise verify your proxy configuration."
                    )
                    [
                      ({
                        assertion =
                          (
                            config ? serviceConfig
                            && config.serviceConfig ? RestrictAddressFamilies
                            && builtins.isList config.serviceConfig.RestrictAddressFamilies
                          )
                          -> builtins.elem "AF_VSOCK" config.serviceConfig.RestrictAddressFamilies;
                        message = ''
                          Unsock: service ${name}: You must whitelist AF_VSOCK within the service unit configuration, otherwise no VSOCK connections will be made.
                          To fix this, set options systemd.services.${name}.serviceConfig.RestrictAddressFamilies = ["AF_VSOCK"];
                        '';
                      })
                      ({
                        assertion =
                          (
                            config ? serviceConfig
                            && config.serviceConfig ? RestrictAddressFamilies
                            && builtins.isString config.serviceConfig.RestrictAddressFamilies
                          )
                          -> lib.hasInfix "AF_VSOCK" config.serviceConfig.RestrictAddressFamilies;
                        message = ''
                          Unsock: service ${name}: You must whitelist AF_VSOCK within the service unit configuration, otherwise no VSOCK connections will be made.
                          To fix this, set options systemd.services.${name}.serviceConfig.RestrictAddressFamilies = "AF_VSOCK";
                        '';
                      })
                    ]
                  ++ (lib.pipe cfg.proxies [
                    (builtins.filter (v: v.match.port != null))
                    (builtins.groupBy ({ match, ... }: toString match.port))
                    (builtins.attrValues)
                    (builtins.map (proxies: {
                      assertion = (builtins.length proxies) == 1;
                      message = ''
                        Unsock: service ${name}: port matcher '${toString (builtins.head proxies).match.port}' is used ${toString (builtins.length proxies)} > 1 times.
                        Fix this by changing one of the ports to a unique value, see options `proesmans.proxies.*.match.port`.
                      '';

                    }))
                  ])
                  ++ (builtins.map (proxy: {
                    assertion =
                      (proxy.to.vsock.cid != null && proxy.to.vsock.port != null)
                      || (proxy.to.vsock.cid == null && proxy.to.vsock.port == null);
                    message = ''
                      Unsock: service ${name}: One of the proxies has incomplete VSOCK details. Either to.vsock.cid and to.vsock.port are both null or both non-null.
                      Fix this by updating the options at `proesmans.proxies.*.to.vsock.{cid, port}`.
                    '';
                  }) (cfg.proxies))
                  ++ (builtins.map (proxy: {
                    assertion =
                      proxy.match.port != null
                      -> proxy.to.socket.path == "${cfg.socket-directory}/${toString proxy.match.port}.sock";
                    message = ''
                      Unsock: service ${name}: The provided socket path '${proxy.to.socket.path}' does not conform the restrictions because IP:PORT matching is configured.
                      To fix this, set options 'proesmans.proxies.*.to.socket.path' to "${cfg.socket-directory}/${toString proxy.match.port}.sock", or set options
                      'proesmans.proxies.*.match.port' to null.
                    '';
                  }) (cfg.proxies))
                );

              unsock.socket-directory = lib.mkIf (cfg.enable) (lib.mkDefault "/run/${name}-unsock");

              environment = lib.optionalAttrs (cfg.enable) {
                UNSOCK_DIR = cfg.socket-directory;
                UNSOCK_ADDR = cfg.ip-scope;
                UNSOCK_ACCEPT_CONVERT_ALL = if cfg.tweaks.accept-convert-all then "1" else "0";
                UNSOCK_ACCEPT_CONVERT_VSOCK = if cfg.tweaks.accept-convert-vsock then "1" else "0";
              };

              serviceConfig = lib.optionalAttrs (cfg.enable) (
                {
                  # ERROR; Cannot add to RestrictAddressFamilies because checking if it's non-empty leads
                  # to infinite recursion!
                  # You must manually add to this attribute if it becomes a problem!
                  # RestrictAddressFamilies = [ "AF_VSOCK" ];

                  # To redirect through AF_VSOCK, a control file must be generated first with the VSOCK details
                  ExecStartPre = builtins.map (
                    proxy:
                    lib.concatStringsSep " " [
                      (lib.getExe generate-vsock-config-script)
                      (lib.escapeShellArg proxy.to.socket.path)
                      (lib.escapeShellArg (toString proxy.to.vsock.cid))
                      (lib.escapeShellArg (toString proxy.to.vsock.port))
                      # Any CID larger that reserved set is assumed to be another (sibling) host, so we want to enable the flag
                      # that passes VSOCK data to the host.
                      (lib.escapeShellArg (if proxy.to.vsock.flag-to-host then "1" else "0"))
                    ]
                  ) (builtins.filter (v: v.to.vsock.cid != null) cfg.proxies);
                }
                // lib.optionalAttrs (cfg.socket-directory == "/run/${name}-unsock") {
                  RuntimeDirectory = [ "${name}-unsock" ];
                  RuntimeDirectoryMode = lib.mkDefault "0750";
                }
              );
            };
        }
      )
    );
  };

  config = {
    # ERROR; Nested assertions aren't evaluated!
    # Passthrough the nested assertions to toplevel, there they are picked up for evaluation.
    assertions = builtins.concatLists (lib.mapAttrsToList (_: v: v.assertions) config.systemd.services);
  };
}
