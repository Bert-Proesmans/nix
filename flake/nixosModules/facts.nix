{ lib, ... }:
{
  options.proesmans.facts = lib.mkOption {
    description = "Host facts.";
    type = lib.types.lazyAttrsOf (
      lib.types.submoduleWith {
        description = "Computer facts module";
        class = "proesmansFacts";
        specialArgs = { };
        modules = [
          (
            { ... }:
            {
              # Allow index-free value declarations
              freeformType = lib.types.attrsOf lib.types.str;

              options = {
                hostName = lib.mkOption {
                  description = "Name of the host";
                  type = lib.types.str;
                };

                domainName = lib.mkOption {
                  description = "Environment name";
                  type = lib.dns.types.domain-name;
                  default = "internal.proesmans.eu";
                };

                encryptedDisks = lib.mkOption {
                  description = "Flag indicating if this host encrypts its storage";
                  type = lib.types.bool;
                  default = false;
                };

                tags = lib.mkOption {
                  description = "";
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  apply = lib.lists.unique;
                };

                hardware = lib.mkOption {
                  description = "Hardware addressing configuration";
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { name, ... }:
                      {
                        options = {
                          address = lib.mkOption {
                            description = ''
                              NOTE; The "locally administrated"-bit must be set for generated virtual MAC addresses!
                              This makes random collisions with global/internationally assigned addresses impossible.
                              REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
                            '';
                            type = lib.net.types.mac;
                            default = name;
                          };

                          tags = lib.mkOption {
                            description = "Extra information bound to the hardware address";
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                            apply = lib.lists.unique;
                          };
                        };
                      }
                    )
                  );
                  default = { };
                };

                host = lib.mkOption {
                  description = "IP addressing configuration";
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { ... }:
                      {
                        options = {
                          address = lib.mkOption {
                            description = "IP Address to reach this service";
                            type = lib.types.nullOr lib.types.str; # TODO; IP-type
                            default = null;
                          };

                          fqdn = lib.mkOption {
                            description = "Fully qualified domain name, preferrably linked to the IP address";
                            type = lib.types.nullOr lib.dns.types.domain-name;
                            default = null;
                          };

                          tags = lib.mkOption {
                            description = "Extra information bound to the hardware address";
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                            apply = lib.lists.unique;
                          };
                        };
                      }
                    )
                  );
                  default = { };
                };

                service = lib.mkOption {
                  description = "Services adressing configuration";
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { name, ... }:
                      {
                        options = {
                          name = lib.mkOption {
                            description = "Friendly name of the service";
                            type = lib.types.str;
                          };

                          port = lib.mkOption {
                            description = "Port number of the service";
                            type = lib.types.nullOr lib.types.int; # TODO; Port-type
                            default = null;
                          };

                          uri = lib.mkOption {
                            description = ''
                              The URI that clients need to use to connect to this service.
                              The value must be a function which receives a hostaddress as the sole argument.
                            '';
                            type = lib.types.nullOr (lib.types.functionTo lib.types.str);
                            default = null;
                            example = lib.literalExpression ''
                              address: "https://''${address}:8001"
                            '';
                          };

                          tags = lib.mkOption {
                            description = "Extra information bound to the service";
                            type = lib.types.listOf (
                              lib.types.either lib.types.str (
                                lib.types.enum [
                                  "dhcp"
                                  "dns"
                                  "webserver"
                                  # TODO
                                ]
                              )
                            );
                            default = [ ];
                            apply = lib.lists.unique;
                          };
                        };
                        config.name = lib.mkDefault name;
                      }
                    )
                  );
                  default = { };
                };
              };

              config = {
                # Not necessary because "config" holds the merged option values up to the submodule barrier.
                # This means it's not possible to read host configuration, nor should it be possible, from within the facts
                # definition file!
                # _module.args.self = config;
              };
            }
          )
        ];
      }
    );
    default = { };
    # Prevent the entire submodule being included in the documentation.
    # visible = "shallow";
  };

  config = {
    # Host config.
    # WARN; Don't set system config based on facts here. This module should work for both standalone facts and nixos configurations.
    # TODO; Figure out (option) conditional config.
  };
}
