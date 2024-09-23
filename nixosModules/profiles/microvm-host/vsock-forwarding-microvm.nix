{ lib, pkgs, config, ... }:
let
  forwarding-guests = lib.filterAttrs (_: v: v.config.config.microvm.vsock.forwarding.enable) config.microvm.vms;
in
{
  config.systemd.services.microvm-vhost-device-vsock = {
    enable = builtins.any (_: true) (lib.mapAttrsToList (_: _: true) forwarding-guests);
    description = "VSOCK Host daemon for MicroVM";
    after = lib.mapAttrsToList (name: _: "install-microvm-${name}.service") forwarding-guests;
    before = lib.mapAttrsToList (name: _: "microvm@${name}.service") forwarding-guests;
    requiredBy = lib.mapAttrsToList (name: _: "microvm@${name}.service") forwarding-guests;
    restartIfChanged = false;

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      User = "microvm";
      Group = "kvm";
      PrivateTmp = "yes";

      RuntimeDirectory = "microvm microvm/vsock";

      ExecStart =
        let
          forwarding-guests-for = my-cid: lib.pipe forwarding-guests [
            (lib.filterAttrs (_: v: builtins.elem my-cid v.config.config.microvm.vsock.forwarding.allowTo))
            (lib.mapAttrsToList (_: v: "group${toString v.config.config.microvm.vsock.forwarding.cid}"))
          ];
          my-groups = my-cid: lib.concatStringsSep "+" ([ "group${toString my-cid}" ] ++ (forwarding-guests-for my-cid));

          vm-args-daemon = name: v:
            let
              cfg = v.config.config.microvm.vsock;
              state-directory = "/var/lib/microvms";
              my-cid = cfg.forwarding.cid;
              control-socket-path = "${state-directory}/${name}/${cfg.forwarding.control-socket}";
              forwarding-socket-path = "/run/microvm/vsock/${name}.vsock";
            in
            lib.concatStringsSep "," ([
              "--vm guest-cid=${toString my-cid}"
              "socket=${control-socket-path}"
              "uds-path=${forwarding-socket-path}"
              #"forward-cid=1" # DEBUG; Forward from guest to 1 (hypervisor)
              #"forward-listen=22+2222" # DEBUG; Forward from host to guest for ports 22+2222
            ]
            ++ (lib.optional cfg.forwarding.freeForAll "groups=default")
            ++ (lib.optional (cfg.forwarding.freeForAll == false) "groups=${my-groups my-cid}")
            );

          script = pkgs.writeShellApplication {
            name = "launch-vhost-daemon";
            runtimeInputs = [ pkgs.proesmans.vhost-device ];
            text = ''
              exec vhost-device-vsock \
                ${lib.concatStringsSep " \\\n  " (lib.mapAttrsToList vm-args-daemon forwarding-guests)}
            '';
          };
        in
        lib.getExe script;
      ExecStartPost =
        let
          # TODO; Just chmod each socket
          script = pkgs.writeShellApplication {
            name = "chmod-sockets";
            runtimeInputs = [ pkgs.findutils pkgs.coreutils ];
            # Allow everyone to write to the sockets created by this service.
            # No other way to specifically change permissions around binding time of the actual socket.. 
            # One of those "yeah, this was never solved" things.
            text = ''
              while ! find /run/microvm/vsock -type s -print -quit; do
                sleep 1  # No better way to wait for socket files to exist ..
              done

              find /run/microvm/vsock -type s -exec chmod 0777 {} +
            '';
          };
        in
        lib.getExe script;
    };
  };
}
