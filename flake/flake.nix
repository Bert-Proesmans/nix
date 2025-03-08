{
  description = "Bert's NixOS configurations";

  # nixConfig.extra-substituters = [ ];
  # nixConfig.extra-trusted-public-keys = [ ];

  inputs = {
    nixpkgs.follows = "nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "path:./flake.systems.nix";
    systems.flake = false;

    # WARN; Seems like everybody is using flake-utils, but this dependency does not bring anything
    # functional without footguns or anything we can't do ourselves.
    # It's imported to simplify/merge the input chain, but unused in this flake.
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";


    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    # Non-versioned home-manager has the best chance to work with the unstable nixpkgs branch.
    # If nixpkgs happens to be stable by default, then also version the home-manager release!
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable"; # == "nixpkgs"
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";
    vscode-server.inputs.flake-utils.follows = "flake-utils";
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    microvm.inputs.flake-utils.follows = "flake-utils";
    dns.url = "github:nix-community/dns.nix";
    dns.inputs.nixpkgs.follows = "nixpkgs";
    dns.inputs.flake-utils.follows = "flake-utils";
    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";
    nix-topology.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, systems, ... }:
    let
      inherit (self) inputs;

      # Shorten calls to library functions;
      # lib.genAttrs == inputs.nixpkgs.lib.genAttrs
      #
      # WARN; inputs.nixpkgs.lib =/= (nixpkgs.legacyPackages.<system> ==) pkgs.lib.
      # In other words, the latter is the nixpkgs library, while the former is
      # the nixpkgs _flake_ lib and this one includes the nixos library functions!
      # eg; inputs.nixpkgs.lib.nixosSystem => exists
      # eg; pkgs.lib.nixosSystem => does _not_ exist
      # eg; nixpkgs.legacyPackages.<system>.lib.nixosSystem => does _not_ exist
      lib = inputs.nixpkgs.lib.extend (inputs.nixpkgs.lib.composeManyExtensions [
        (_: _: { dns = inputs.dns.lib; }) # lib from dns.nix
        (_: _: self.outputs.lib) # Our own lib
      ]);

      __forSystems = lib.genAttrs (import systems);
      __forPackages = __forSystems (system: inputs.nixpkgs.legacyPackages.${system});
      eachSystem = mapFn: __forSystems (system: mapFn __forPackages.${system});
    in
    {
      lib = import ./library/all.nix { inherit inputs lib; };

      formatter = eachSystem (pkgs: import ./formatters.nix { inherit inputs pkgs; });

      devShells = eachSystem (pkgs: import ./devshells.nix { inherit pkgs lib; });

      overlays = { };

      nixosModules = self.outputs.lib.rakeLeaves ./nixosModules;
      homeModules = self.outputs.lib.rakeLeaves ./homeModules;

      hostInventory = import ./host-inventory.nix;
      nixosConfigurations = import ./nixosConfigurations/all.nix { inherit lib; flake = self; };
      # no homeConfigurations

      packages = eachSystem (pkgs: import ./packages/all.nix { inherit pkgs; });

      checks = { };
      hydraJobs = eachSystem
        (pkgs: {
          recurseForDerivations = true;
          formatter = self.outputs.formatter.${pkgs.system};
          devShells = self.outputs.devShells.${pkgs.system};
          packages = self.outputs.packages.${pkgs.system};
          checks = self.outputs.checks.${pkgs.system};
        }) // {
        no-system.recurseForDerivations = true;
        no-system.nixosConfigurations = lib.mapAttrs (_: v: v.config.system.build.toplevel) self.outputs.nixosConfigurations;
      };
    };
}
