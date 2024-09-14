{ modulesPath, lib, pkgs, config, ... }:
let
  cfg = config.proesmans.vsock-proxy;

  socket-details = { lib, config, ... }: {
    options = {
      tcp.ip = lib.mkOption {
        description = "IP address";
        type = lib.types.nullOr lib.net.types.ipv4;
        default = null;
      };

      vsock.cid = lib.mkOption {
        description = ''
          VSOCK host ID. This value is ignored when listening on a VSOCK.
          CONSTANTS for connecting to a VSOCK listener;
            - VMADDR_CID_HYPERVISOR = 0 (AKA deprecated) **do not use**
            - VMADDR_CID_LOCAL = 1 (AKA loopback)
            - VMADDR_CID_HOST = 2 (AKA hypervisor)

          ERROR; Binding/connecting to VMADDR_CID_LOCAL requires loaded kernel module "vhost_loopback"
          so the loopback transport is available. If the module is not loaded, connections will never
          complete AKA a silent "failure".
        '';
        type = lib.types.nullOr (lib.types.addCheck lib.types.int (x: x == -1 || x > 0));
        default = null;
      };

      port = lib.mkOption {
        description = "Port";
        type = lib.types.port;
      };
    };

    config.assertions = [
      {
        assertion = (config.tcp.ip == null && config.vsock.cid == null)
          || (config.tcp.ip != null && config.vsock.cid != null);
        message = ''
          Either one of the transports TCP or VSOCK must be configured!
          To fix this, set one of the options tcp.ip or vsock.cid to a valid value and clear the other.
        '';
      }
    ];
  };
in
{
  options.proesmans.vsock-proxy = {
    package = lib.mkPackageOption pkgs "socat" { };

    proxies = lib.mkOption {
      description = "Connect bidirectionally between VSOCK and TCP";
      default = [ ];
      type = lib.types.listOf (lib.types.submodule ({ ... }: {
        options = {
          enable = lib.mkEnableOption "vsock<->tcp proxy" // { default = true; };

          description = lib.mkOption {
            description = "Description assigned to the service";
            type = lib.types.nullOr lib.types.singleLineStr;
            default = null;
          };

          listen = lib.mkOption {
            description = "Listener side, accepting new connections";
            type = lib.types.submodule [
              # Must include since submodule is scope-isolated
              "${modulesPath}/misc/assertions.nix"
              socket-details
            ];
          };
          transmit = lib.mkOption {
            description = "Transmit side, where the data is proxied to";
            type = lib.types.submodule [
              # Must include since submodule is scope-isolated
              "${modulesPath}/misc/assertions.nix"
              socket-details
            ];
          };
        };
      }));
    };
  };

  config = {
    systemd.services = lib.mkMerge (lib.flip lib.imap1 cfg.proxies
      (i: v: {
        "vsock-proxy-${toString i}" =
          let
            capabilities = lib.optionals (v.listen.port < 1024) [ "CAP_NET_BIND_SERVICE" ];
          in
          {
            enable = v.enable;
            description = lib.mkIf (v.description != null) v.description;
            before = [ "multi-user.target" ];
            wantedBy = [ "multi-user.target" ];

            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "10";
              AmbientCapabilities = capabilities;
              CapabilityBoundingSet = capabilities;
              DynamicUser = true;
              ExecStart =
                let
                  # NOTE; Port is added below, since it always exists
                  source-argument =
                    if v.listen.tcp.ip != null
                    then "TCP4-LISTEN:${toString v.listen.port},bind=${v.listen.tcp.ip},reuseaddr,fork"
                    else "VSOCK-LISTEN:${toString v.listen.port},reuseaddr,fork";
                  destination-argument =
                    if v.transmit.tcp.ip != null
                    then "TCP4-CONNECT:${v.transmit.tcp.ip}:${toString v.transmit.port}"
                    else "VSOCK-CONNECT:${toString v.transmit.vsock.cid}:${toString v.transmit.port}";
                in
                builtins.concatStringsSep " " [
                  (lib.getExe cfg.package)
                  source-argument
                  destination-argument
                ];
            };
          };
      })
    );
  };
}
