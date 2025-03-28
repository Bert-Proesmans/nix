{ lib, ... }: {
  options.proesmans.facts = lib.mkOption {
    description = "Host facts.";
    type = lib.types.submoduleWith {
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
              ]);
              default = [ ];
            };

            management.mac-address = lib.mkOption {
              description = ''
                The MAC address of the network interface that should be used for SSH host management.
            
                NOTE; The "locally administrated"-bit must be set for generated virtual MAC addresses!
                This makes random collisions with internationally assigned address impossible.
                REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
              '';
              type = lib.types.nullOr lib.net.types.mac;
              default = null;
            };
          };
          config = {
            # Facts config.
          };
        })
      ];
    };
    default = { };
    # Prevent the entire submodule being included in the documentation.
    # visible = "shallow";
  };

  config = {
    # Host config.
  };
}
