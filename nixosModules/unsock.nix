{ lib, pkgs, modulesPath, config, ... }:
let
  # Settings per proxy address
  proxy-settings-unsock = { lib, config, ip-scope-parent, socket-directory-parent, ... }: {
    options = {
      match.ip = lib.mkOption {
        description = "The IP address to match and perform a redirect";
        type = lib.net.types.cidrv4-in ip-scope-parent;
        default = "127.175.0.0";
      };

      match.port = lib.mkOption {
        description = "The port to match and perform a redirect";
        type = lib.types.port;
      };

      to.socket = lib.mkOption {
        description = ''
          The socket file to redirect to.
          Manually create a unix socket at this path manually, or fill in options `to.vsock.{cid,port}` to
          automatically create files instructing to redirect through AF_VSOCK.

          This property is readonly because;    
          
          * The socket directory must be the same for all proxies within the same process
          * The filename calculation is hardcoded within the library so and must be adhered to
        '';
        type = lib.types.path;
        default = "${socket-directory-parent}/${toString config.match.port}.sock";
        readOnly = true;
      };

      to.vsock.cid = lib.mkOption {
        description = ''
          VSOCK host ID. Note that hosts could have multiple aliased IDs.
          CONSTANTS;
            - VMADDR_CID_HYPERVISOR = 0 (AKA deprecated)
            - VMADDR_CID_LOCAL = 1 (AKA loopback)
            - VMADDR_CID_HOST = 2 (AKA hypervisor)
        '';
        type = lib.types.nullOr lib.types.ints.u32;
        default = null;
      };

      to.vsock.port = lib.mkOption {
        description = "VSOCK Port to redirect to";
        type = lib.types.nullOr lib.types.port;
        default = null;
      };
    };
  };
in
{
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
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
          type = lib.types.listOf (lib.types.submodule [
            proxy-settings-unsock
            ({
              _module.args.ip-scope-parent = config.unsock.ip-scope;
              _module.args.socket-directory-parent = config.unsock.socket-directory;
            })
          ]);
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
              Take variables from environment or overwrite them from command line
              export UNSOCK_FILE="''${1:-UNSOCK_FILE}"
              export UNSOCK_VSOCK_CID="''${2:-UNSOCK_VSOCK_CID}"
              export UNSOCK_VSOCK_PORT="''${3:-UNSOCK_VSOCK_PORT}"

              [ -e "$UNSOCK_FILE" ] && rm --force "$UNSOCK_FILE"

              Execute the library, creating a config file at UNSOCK_FILE with provided details
              libunsock.so

              chmod 0600 "$UNSOCK_FILE"
            '';
          };
        in
        {
          assertions =
            let
              by-socket-proxies = builtins.attrValues (builtins.groupBy ({ to, ... }: to.socket) cfg.proxies);
              by-vsock-proxies = builtins.attrValues (builtins.groupBy ({ to, ... }: "${toString to.vsock.cid}-${toString to.vsock.port}") cfg.proxies);
            in
            lib.optionals (cfg.enable) (
              (lib.warnIf (builtins.any (v: builtins.length v > 1) by-socket-proxies)
                "Unsock: service ${name}: You have multiple proxies pointing to the same socket path. This could be intentional, otherwise verify your proxy configuration."
                [ ])
              ++ (lib.warnIf (builtins.any (v: builtins.length v > 1) by-vsock-proxies)
                "Unsock: service ${name}: You have multiple proxies pointing to the same VSOCK listener. This could be intentional, otherwise verify your proxy configuration."
                [ ])
              ++ (builtins.map
                (proxies: {
                  assertion = (builtins.length proxies) == 1;
                  message = ''
                    Unsock: service ${name}: port matcher '${toString (builtins.head proxies).match.port}' is used ${toString (builtins.length proxies)} > 1 times.
                    Fix this by changing one of the ports to a unique value, see options `proesmans.proxies.*.match.port`.
                  '';
                })
                (builtins.attrValues (builtins.groupBy ({ match, ... }: toString match.port) cfg.proxies)))
              ++ builtins.map
                (proxy: {
                  assertion = (proxy.to.vsock.cid != null && proxy.to.vsock.port != null)
                  || (proxy.to.vsock.cid == null && proxy.to.vsock.port == null);
                  message = ''
                    Unsock: service ${name}: One of the proxies has incomplete VSOCK details. Either to.vsock.cid and to.vsock.port are both null or both non-null.
                    Fix this by updating the options at `proesmans.proxies.*.to.vsock.{cid, port}`.
                  '';
                })
                (cfg.proxies)
            );

          unsock.socket-directory = lib.mkIf (cfg.enable) (lib.mkDefault "/run/${name}-unsock");

          environment = lib.optionalAttrs (cfg.enable) {
            UNSOCK_DIR = cfg.socket-directory;
            UNSOCK_ADDR = cfg.ip-scope;
          };

          serviceConfig = lib.optionalAttrs (cfg.enable) ({
            # ERROR; Cannot add to RestrictAddressFamilies because checking if it's non-empty leads
            # to infinite recursion!
            # You must manually add to this attribute if it becomes a problem!
            # RestrictAddressFamilies = [ "AF_VSOCK" ];

            # To redirect through AF_VSOCK, a control file must be generated first with the VSOCK details
            ExecStartPre = builtins.map
              (proxy: lib.concatStringsSep " " [
                (lib.getExe generate-vsock-config-script)
                (lib.escapeShellArg proxy.to.socket)
                (lib.escapeShellArg (toString proxy.to.vsock.cid))
                (lib.escapeShellArg (toString proxy.to.vsock.port))
              ])
              (builtins.filter (v: v.to.vsock.cid != null) cfg.proxies);
          }
          // lib.optionalAttrs (cfg.socket-directory == "/run/${name}-unsock") {
            RuntimeDirectory = [ "${name}-unsock" ];
            RuntimeDirectoryMode = lib.mkDefault "0750";
          });
        };
    }));
  };

  config = {
    # ERROR; Nested assertions aren't evaluated!
    # Passthrough the nested assertions to toplevel, there they are picked up for evaluation.
    assertions = builtins.concatLists (lib.mapAttrsToList (_: v: v.assertions) config.systemd.services);
  };
}
