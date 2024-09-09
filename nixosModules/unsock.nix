{ lib, pkgs, config, ... }:
let
  cfg = config.proesmans.unsock;
in
{
  options.proesmans.unsock = {
    enable = lib.mkEnableOption "redirecting AF_INET into AF_UNIX/AF_VSOCK";
    package = lib.mkPackageOption pkgs [ "proesmans" "unsock" ] { };

    user = lib.mkOption {
      description = "User account under which the socket directory is installed.";
      type = lib.types.str;
      default = "unsock";
    };

    group = lib.mkOption {
      description = "Group account under which the socket directory is installed.";
      type = lib.types.str;
      default = "unsock";
    };

    socket-directory = lib.mkOption {
      description = "Directory where the sockets are installed";
      type = lib.types.path;
      default = "/run/unsock";
    };

    wrappers.nginx = {
      enable = lib.mkEnableOption "wrapping nginx with unsock" // { default = true; };
      package = lib.mkPackageOption pkgs [ "nginxMainline" ] { };
    };

    ip-scope = lib.mkOption {
      description = "The scope of IP addresses which are translated into sockets";
      type = lib.net.types.cidrv4;
      default = "127.175.0.0/32";
    };

    proxies = lib.mkOption {
      description = "";
      default = [ ];
      type = lib.types.listOf (lib.types.submodule ({ name, config, ... }: {
        options = {
          match.ip = lib.mkOption {
            description = "The IP address to match and perform a redirect";
            type = lib.net.types.cidrv4-in cfg.ip-scope;
            default = "127.175.0.0";
          };

          match.port = lib.mkOption {
            description = "The port to match and perform a redirect";
            type = lib.types.port;
          };

          to.socket = lib.mkOption {
            description = ''
              The socket file to redirect to.  
              
              The socket directory must be the same for all proxies.  
              The filename calculation is hardcoded within the library so that must be adhered to.
            '';
            type = lib.types.path;
            default = "${cfg.socket-directory}/${toString config.match.port}.sock";
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
            type = lib.type.nullOr lib.types.port;
            default = null;
          };
        };
      }));
    };
  };

  config =
    let
      generate-vsock-config-script = pkgs.writeShellApplication {
        name = "generate-vsock-config";
        runtimeInputs = [ cfg.package ];
        text = ''
          # Take variables from environment or overwrite them from command line
          export UNSOCK_FILE="''${1:-UNSOCK_FILE}"
          export UNSOCK_VSOCK_CID="''${2:-UNSOCK_VSOCK_CID}"
          export UNSOCK_VSOCK_PORT="''${3:-UNSOCK_VSOCK_PORT}"

          [ -e "$UNSOCK_FILE" ] && rm --force "$UNSOCK_FILE"

          # Execute the library, creating a config file at UNSOCK_FILE with provided details
          libunsock.so

          chmod 0600 "$UNSOCK_FILE"
        '';
      };
    in
    lib.mkIf cfg.enable {
      assertions =
        let
          by-socket-proxies = builtins.attrValues (builtins.groupBy ({ to, ... }: to.socket) cfg.proxies);
          by-vsock-proxies = builtins.attrValues (builtins.groupBy ({ to, ... }: "${toString to.vsock.cid}-${toString to.vsock.port}") cfg.proxies);
        in
        [ ]
        ++ (lib.warnIf (builtins.any (v: builtins.length v > 1) by-socket-proxies)
          "You have multiple proxies pointing to the same socket path. This could be intentional, otherwise verify your proxy configuration."
          [ ])
        ++ (lib.warnIf (builtins.any (v: builtins.length v > 1) by-vsock-proxies)
          "You have multiple proxies pointing to the same VSOCK listener. This could be intentional, otherwise verify your proxy configuration."
          [ ])
        ++ (builtins.map
          (proxies: {
            assertion = (builtins.length proxies) == 1;
            message = ''
              Unsock: port matcher '${toString (builtins.head proxies).match.port}' is used ${toString (builtins.length proxies)} > 1 times.
              Fix this by changing one of the ports to a unique value, see options `proesmans.proxies.*.match.port`.
            '';
          })
          (builtins.attrValues (builtins.groupBy ({ match, ... }: toString match.port) cfg.proxies)))

        ++ builtins.map
          (proxy: {
            assertion = (proxy.to.vsock.cid != null && proxy.to.vsock.port != null)
            || (proxy.to.vsock.cid == null && proxy.to.vsock.port == null);
            message = ''
              Unsock: One of the proxies has incomplete VSOCK details. Either to.vsock.cid and to.vsock.port are both null or both non-null.
              Fix this by updating the options at `proesmans.proxies.*.to.vsock.{cid, port}`.
            '';
          })
          (cfg.proxies)
      ;

      users.users.unsock = lib.mkIf (cfg.user == "unsock") {
        group = cfg.group;
        isSystemUser = true;
      };

      users.groups.unsock = lib.mkIf (cfg.group == "unsock") { };

      systemd.tmpfiles.settings."1-unsock" = {
        "${cfg.socket-directory}" = {
          # Remove contents at boot
          "e!".age = "0";
          d = {
            user = cfg.user;
            group = cfg.group;
            # Allow user and group to read-write
            # WARN; Socket files themselves must have at least 660 permission to work!
            #
            # NOTE; Includes sticky bit to prevent users from deleting others files
            mode = "1770";
          };
        };
      };

      nixpkgs.overlays = lib.optional (cfg.wrappers.nginx.enable) (final: prev: {
        # Create a custom NGINX package where IPs get redirected into AF_UNIX and AF_VSOCK
        #
        # ERROR; Cannot add packages in deeper scope, AKA proesmans.XXX doesn't work!
        # Keep new additions in toplevel scope.
        xx-unsocked-nginx = cfg.wrappers.nginx.package.overrideAttrs (prevAttrs: {
          nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

          postInstall = (prevAttrs.postInstall or "") + ''
            wrapProgram $out/bin/nginx \
               --prefix LD_PRELOAD : ${lib.getLib cfg.package}/lib/libunsock.so
          '';
        });
      });

      users.users.nginx.extraGroups = lib.optional (cfg.wrappers.nginx.enable) cfg.group;
      services.nginx.package = lib.mkIf (cfg.wrappers.nginx.enable) pkgs.xx-unsocked-nginx;
      systemd.services.nginx = lib.mkIf (cfg.wrappers.nginx.enable) {
        environment = {
          UNSOCK_DIR = cfg.socket-directory;
          UNSOCK_ADDR = cfg.ip-scope;
        };

        # Upstream unit config restricts VSOCK usage, so we need to loosen the constraint
        serviceConfig.RestrictAddressFamilies = [ "AF_VSOCK" ];

        # To redirect through AF_VSOCK, a control file must be generated first with the VSOCK details
        serviceConfig.ExecStartPre = builtins.map
          (proxy: lib.concatStringsSep " " [
            (lib.getExe generate-vsock-config-script)
            (lib.escapeShellArg proxy.to.socket)
            (lib.escapeShellArg (toString proxy.to.vsock.cid))
            (lib.escapeShellArg (toString proxy.to.vsock.port))
          ])
          (builtins.filter (v: v.to.vsock.cid != null) cfg.proxies);
      };
    };
}
