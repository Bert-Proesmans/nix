{ lib, ... }: {
  options.proesmans.facts = lib.mkOption {
    description = "Host facts.";
    type = lib.types.lazyAttrsOf (lib.types.submoduleWith {
      description = "Computer facts module";
      class = "proesmansFacts";
      specialArgs = { };
      modules = [
        ({ ... }: {
          # Allow index-free value declarations
          freeformType = lib.types.attrsOf lib.types.str;

          options = {
            domainName = lib.mkOption {
              description = "Internal environment name of this host";
              type = lib.dns.types.domain-name;
              default = "internal.proesmans.eu";
            };

            hostAliases = lib.mkOption {
              description = "This host is accessible through one or more of these domain names";
              type = lib.types.listOf lib.dns.types.domain-name;
              default = [ ];
            };

            tags = lib.mkOption {
              description = "";
              type = lib.types.listOf lib.types.str;
              apply = lib.lists.unique;
              default = [ ];
            };

            services = lib.mkOption {
              description = "Services provided by this host";
              type = lib.types.listOf (lib.types.enum [
                "dhcp"
                "dns"
                "webserver"
                # TODO
              ]);
              default = [ ];
            };

            macAddresses = lib.mkOption {
              description = "The MAC addresses that reach this host";
              type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
                options = {
                  address = lib.mkOption {
                    description = ''
                      NOTE; The "locally administrated"-bit must be set for generated virtual MAC addresses!
                      This makes random collisions with internationally assigned address impossible.
                      REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
                    '';
                    type = lib.net.types.mac;
                    default = name;
                  };
                  tags = lib.mkOption {
                    description = "";
                    type = lib.types.listOf (lib.types.enum [
                      "management"
                      "service"
                      # TODO
                    ]);
                    apply = lib.lists.unique;
                  };
                };
              }));
              default = { };
            };
          };
          config = {
            # Facts config.
          };
        })
      ];
    });
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
