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
      # WARN; The created sockets MUST be writeable by everyone to mimic system driver VSOCK!
      UMask = "000";
      RuntimeDirectory = "microvm microvm/vsock";

      ExecStart =
        let
          my-groups = guest:
            let
              cfg = guest.config.config.microvm.vsock;
              my-cid = cfg.forwarding.cid;
              i-forward-to = cfg.forwarding.allowTo;
            in
            lib.concatStringsSep "+" (
              [ "group${toString my-cid}" ]
              ++ (builtins.map (x: "group${toString x}") i-forward-to)
            );

          vm-args-daemon = name: guest:
            let
              cfg = guest.config.config.microvm.vsock;
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
            ++ (lib.optional (cfg.forwarding.freeForAll == false) "groups=${my-groups guest}")
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
      # I made an oopsie and UMask update is enough to make the sockets world writeable..
      # ExecStartPost =
      #   let
      #     chmod-sock-script = socket-basename: ''
      #       while ! find /run/microvm/vsock -type s -name ${socket-basename} -exec chmod 0777 {} \;
      #       do
      #         sleep 1  # No better way to wait for socket files to exist ..
      #       done
      #     '';
      #     script = pkgs.writeShellApplication {
      #       name = "chmod-sockets";
      #       runtimeInputs = [ pkgs.findutils pkgs.coreutils ];
      #       # Allow everyone to write to the sockets created by this service.
      #       # No other way to specifically change permissions around binding time of the actual socket.. 
      #       # One of those "yeah, this was never solved" things.
      #       text = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: chmod-sock-script "${name}.vsock") forwarding-guests);
      #     };
      #   in
      #   lib.getExe script;
    };
  };
}
