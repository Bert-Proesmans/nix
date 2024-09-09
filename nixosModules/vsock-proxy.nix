{ modulesPath, lib, pkgs, config, ... }:
let
  cfg = config.proesmans.vsock-proxy;

  socket-details = { lib, config, ... }: {
    options = {
      tcp.ip = lib.mkOption {
        description = "IP address";
        type = lib.types.nullOr lib.net.types.ip;
        default = null;
      };

      vsock.cid = lib.mkOption {
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
    package = lib.mkPackageOption pkgs [ "proesmans" "vsock-proxy" ] { };

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
                  source-argument =
                    if v.listen.tcp.ip != null
                    then "--tcp-source ${v.listen.tcp.ip}"
                    else "--vsock-source ${toString v.listen.vsock.cid}";
                  destination-argument =
                    if v.transmit.tcp.ip != null
                    then "--tcp-dest ${v.transmit.tcp.ip}"
                    else "--vsock-dest ${toString v.transmit.vsock.cid}";
                in
                builtins.concatStringsSep " " [
                  "${lib.getExe cfg.package}"
                  "${source-argument}:${toString v.listen.port}"
                  "${destination-argument}:${toString v.transmit.port}"
                ];
            };
          };
      })
    );
  };
}
