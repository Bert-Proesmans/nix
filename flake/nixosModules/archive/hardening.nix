{ lib, config, ... }:
let
  cfg = config.proesmans.hardening;
in
{
  options.proesmans.hardening.enable-all = lib.mkEnableOption "Hardened configuration";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable-all {
      services.resolved.fallbackDns = [
        "127.0.0.1"
        "::1"
      ];
      services.resolved.llmnr = "false";
      services.resolved.dnsovertls = "true";
      services.resolved.domains = [
        # Look in the root domain, aka do not append a domain suffix
        "~."
      ];
      services.resolved.extraConfig = [
        # Disable binding to loopback interface and act as a intermediate resolver
        "DNSStubListener=no"
      ];
    })
  ];
}
