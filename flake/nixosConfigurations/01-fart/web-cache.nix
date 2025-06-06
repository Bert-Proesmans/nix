{ lib, ... }: {
  services.varnish = {
    enable = true;
    # Varnish actually checks if the backend resolves to an IP correctly, from the build host!
    enableConfigCheck = false; # DEBUG
    # http_address = "uds=/run/varnish/frontend.sock,PROXY,mode=666";
    http_address = "uds=/run/varnish/frontend.sock,HTTP,mode=666";
    config = builtins.readFile ./default.vcl;
    extraCommandLine = "-s file,/var/cache/varnishd,40G";
  };

  systemd.services.varnish = {
    serviceConfig.CacheDirectory = "varnishd";
    serviceConfig.RuntimeDirectory = lib.mkForce [ "varnishd" "varnish" ];
  };
}
