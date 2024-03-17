# This is a nixos module.  NixOSArgs -> AttrSet
{ config, lib, options, ... }:
let
  cfg = config.proesmans.networks;
  opt = options.proesmans.networks;
in
{
  options.proesmans.networks = {
    # management = {
    #   dhcp.enable = lib.mkEnableOption (lib.mdDoc "Enable DHCP on the management interface");
    #   subnet = lib.mkOption {
    #     type = lib.net.types.cidr;
    #     default = null;
    #     description = lib.mdDoc ''
    #       The subnet address to be assigned to the management interface of the machine.
    #     '';
    #   };
    #   ip = lib.mkOption {
    #     type = lib.net.types.ip-in cfg.networks.management.subnet;
    #     default = null;
    #     description = lib.literalMD ''
    #       The IP, which must be inside the subnet provided by option config.${opt.networks.management.subnet}.
    #     '';
    #   };
    #   mac = lib.mkOption {
    #     type = lib.net.types.mac;
    #     default = null;
    #     description = lib.mdDoc ''
    #       The MAC address to identify the management adapter by.
    #     '';
    #   };
    # };

    # service = {
    #   dhcp.enable = lib.mkEnableOption (lib.mdDoc "Enable DHCP on the service interface");
    #   subnet = lib.mkOption {
    #     type = lib.net.types.cidr;
    #     default = null;
    #     description = lib.mdDoc ''
    #       The subnet address to be assigned to the service interface of the machine.
    #     '';
    #   };
    #   ip = lib.mkOption {
    #     type = lib.net.types.ip-in cfg.networks.service.subnet;
    #     default = null;
    #     description = lib.literalMD ''
    #       The IP, which must be inside the subnet provided by option config.${opt.networks.service.subnet}.
    #     '';
    #   };
    #   mac = lib.mkOption {
    #     type = lib.net.types.mac;
    #     default = null;
    #     description = lib.mdDoc ''
    #       The MAC address to identify the service adapter by.
    #     '';
    #   };
    # };
  };

  config = {
    # systemd.network.enable = true;
    # # Create routing tables for policy routing, these tables can be referenced by name within the
    # # systemd network configuration.
    # systemd.network.config.routeTables.management = 101;
    # systemd.network.config.routeTables.service = 103;
    # # Policy routing #
    # # REF; https://unix.stackexchange.com/a/589133
    # # In a multihomed network setup it's important to select the target interface based on the source IP address.
    # # Normal routing looks at the destination IP, which basically results in picking the default gateway route for out-of-subnet
    # # destinations. Then there is also the security measure 'reverse path filtering'.
    # # The solution is to bind routing tables to the interfaces, and put a default gateway on each routing table, and perform some
    # # packet mangling based on source IP address.
    # #
    # # Alternative link names #
    # # The latest kernels support alternative names for the network interfaces. These alternative names can
    # # be used in static configuration like routes and firewall.
    # # ERROR; An alternative name isn't always applied/updated without a system reboot.
    # #
    # systemd.network.links = {
    #   "10-management" = {
    #     matchConfig.MACAddress = "96:b0:5f:34:a9:9a";
    #     linkConfig.AlternativeName = "management";
    #   };
    #   "10-applications" = {
    #     matchConfig.MACAddress = "16:f0:e8:22:8e:5f";
    #     linkConfig.AlternativeName = "service";
    #   };
    # };
    # systemd.network.networks = {
    #   "30-management" = {
    #     matchConfig.MACAddress = "96:b0:5f:34:a9:9a";
    #     networkConfig.IPv6AcceptRA = true; # <== Default gateway
    #     address = [ "10.1.7.11/24" "fd83:c0cd:d5c2:8::10/64" ];
    #     gateway = [ "10.1.7.1" ]; # <== Default gateway
    #     # dns = [ "127.0.0.1" "::1" ];
    #     routes = [
    #       {
    #         routeConfig.Gateway = "10.1.7.1";
    #         routeConfig.Table = "management";
    #       }
    #       {
    #         routeConfig.Gateway = "fd83:c0cd:d5c2:8::1";
    #         routeConfig.Table = "management";
    #       }
    #     ];
    #     routingPolicyRules = [
    #       {
    #         routingPolicyRuleConfig.From = " 10.1.7.11";
    #         routingPolicyRuleConfig.Table = "management";
    #       }
    #       {
    #         routingPolicyRuleConfig.From = " fd83:c0cd:d5c2:8::10 ";
    #         routingPolicyRuleConfig.Table = "management";
    #       }
    #     ];
    #   };
    #   "30-applications" = {
    #     matchConfig.MACAddress = " 16:f0:e8:22:8e:5f";
    #     networkConfig.IPv6AcceptRA = false;
    #     address = [ "10.1.23.10/24" "fd83:c0cd:d5c2:14::11/64" ];
    #     routes = [
    #       {
    #         routeConfig.Gateway = "10.1.23.1";
    #         routeConfig.Table = "service";
    #       }
    #       {
    #         routeConfig.Gateway = "fd83:c0cd:d5c2:14::1";
    #         routeConfig.Table = "service";
    #       }
    #     ];
    #     routingPolicyRules = [
    #       {
    #         routingPolicyRuleConfig.From = "10.1.23.10";
    #         routingPolicyRuleConfig.Table = "service";
    #       }
    #       {
    #         routingPolicyRuleConfig.From = "fd83:c0cd:d5c2:14::11";
    #         routingPolicyRuleConfig.Table = "service";
    #       }
    #     ];
    #   };
    # };
  };
}
