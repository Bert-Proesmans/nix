{ lib, ... }: {
  options.proesmans.facts = lib.mkOption {
    description = "Host facts.";
    type = lib.types.submoduleWith {
      description = "Computer facts module";
      class = "proesmansFacts";
      specialArgs = { };
      modules = [
        ({ ... }: {
          options = {
            hostName = lib.mkOption {
              description = "";
              type = lib.types.str;
            };

            domainName = lib.mkOption {
              description = "Domain of the environment of this host, value must conform to the rules of a DNS name";
              type = lib.dns.types.domain-name;
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
