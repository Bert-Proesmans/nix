{ lib, pkgs, config, ... }:
let
  # ERROR; Infinite recursion
  # any-unsock-enabled = builtins.any (v: v == true) (lib.mapAttrsToList (_: v: v.unsock.enable) config.systemd.services);
  cfg = config.proesmans.fixes.unsock-nginx;
in
{

  options.proesmans.fixes.unsock-nginx = {
    enable = lib.mkEnableOption "unsock'able nginx";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        # Do this for all nginx packages, why are there so many .. 
        nginxStable = prev.nginxStable.overrideAttrs (old: {
          # Forcefully add poll module for event handling. This method can be used with UNSOCK
          configureFlags = old.configureFlags ++ [ "--with-poll_module" ];
        });
      })
    ];

    services.nginx.eventsConfig = ''
      # ERROR; epoll event method doesn't work with socket rebind
      # REF; https://github.com/kohlschutter/unsock/issues/2#issuecomment-2380074418
      use poll;
    '';
  };
}
