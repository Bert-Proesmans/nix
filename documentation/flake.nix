rec {
  description = "Bert Proesmans's homelab documentation";

  inputs = {
    configuration.url = "github:Bert-Proesmans/nix";
    nixpkgs.follows = "configuration/nixpkgs";
    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, ... }:
    let
      inherit (self) inputs;
      inherit (inputs.nixpkgs) lib;

      __forSystems = lib.genAttrs [ "x86_64-linux" ];
      __forPackages = __forSystems (
        system:
        (import (inputs.nixpkgs) {
          localSystem = { inherit system; };
          overlays = [ inputs.nix-topology.overlays.default ];
        })
      );
      # Helper creating attribute sets for each supported system.
      eachSystem = mapFn: __forSystems (system: mapFn __forPackages.${system});
    in
    {
      # Render your topology via the command below, the resulting directory will contain your finished svgs.
      # nix build .#topology.x86_64-linux.config.output
      #
      # Constructs a visual topology of all the host configurations inside this flake. The code uses evalModules, which is the same
      # "platform" used by nixosSystem to process module files.
      topology = eachSystem (
        pkgs:
        import inputs.nix-topology {
          inherit pkgs;
          modules = [
            # HELP; You own file to define global topology. Works in principle like a nixos module but uses different options.
            (
              { config, ... }:
              let
                inherit (config.lib.topology) mkInternet mkRouter mkConnection;
              in
              {
                _file = ./flake.nix;
                config = {
                  # WARN; Provide all nixosConfigurations definitions
                  nixosConfigurations = inputs.configuration.nixosConfigurations;

                  nodes.internet = mkInternet {
                    connections = mkConnection "router" "ether1";
                  };

                  nodes.router = mkRouter "Mikrotik" {
                    info = "RB750Gr3";
                    image = ./assets/RB750Gr3-smol.png;
                    interfaceGroups = [
                      [
                        "ether2"
                        "ether3"
                        "ether4"
                        "ether5"
                      ]
                      [ "ether1" ]
                    ];
                    #connections.ether2 = mkConnection "buddy" "30-lan"; # TODO
                    interfaces.ether2 = {
                      addresses = [ "192.168.88.1" ];
                      network = "home";
                    };
                  };

                  networks.home = {
                    name = "Home Network";
                    cidrv4 = "192.168.88.0/24";
                  };
                };
              }
            )
          ];
        }
      );
    };
}
