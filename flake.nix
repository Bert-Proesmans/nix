{
	description = "Bert Proesmans's NixOS configuration";

	inputs = {
		nixpkgs.follows = "nixos-stable";
		nixos-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
		nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

		nixos-generators.url = "github:nix-community/nixos-generators";
    	nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

		home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";

		disko.url = "github:nix-community/disko";
    	disko.inputs.nixpkgs.follows = "nixpkgs";

        srvos.url = "github:nix-community/srvos";
        srvos.inputs.nixpkgs.follows = "nixpkgs";
        # Use the version of nixpkgs that has been tested to work with SrvOS
        # nixpkgs.follows = "srvos/nixpkgs";

        vscode-server.url = "github:nix-community/nixos-vscode-server";
	};

	outputs = { self, nixpkgs, ... } @ inputs:
    let
        # default-system = nixpkgs.lib.systems.examples.gnu64
        inherit (self) outputs;

        # Amalgamation of utility functions
        lib' = nixpkgs.lib.extend (final: prev: import ./library { lib = prev; });
		modules = lib'.rakeLeaves ./modules;

        makeInstaller = target-host: (lib'.makeOverridable lib'.nixosSystem) {
            specialArgs = {inherit inputs target-host; inherit (self) outputs;};
            modules = [
                outputs.nixosModules.install-iso
                outputs.nixosModules.interactive-install
                outputs.nixosModules.strip-on-virtualisation
                outputs.nixosModules.be-internationalisation
                ({lib, ...}: {
                    # Platform tuple of installer is bound to the one of the system installed. It doesn't make sense to
                    # have the installer built for another platform.
                    nixpkgs.hostPlatform = lib.mkForce target-host.pkgs.stdenv.hostPlatform;

                    # Passthrough optimizations
                    virtualisation.hypervGuest.enable = target-host.config.virtualisation.hypervGuest.enable;
                })
            ];
        };
    in
	{
        lib = import ./library {inherit (nixpkgs) lib;};

        # formatter = lib'.genAttrs supportedSystems (s: nixpkgs.legacyPackages.${s}.treefmt);

        inherit modules;
        nixosModules = self.modules.nixos;

        # nix build .#nixosConfigurations."<name>".config.system.build.toplevel
        # nixos-rebuild switch --flake /home/<user>/flake#hostname
        # nixos-rebuild switch --flake .#<name> --target-host "<nixos-host.domain.tld>"
        # IMPORTANT; Everything is built from _and into_ the nix store. The partition where /nix resides could become full
        # and block you from upgrading/changing the system. If you ever encounter space issues;
        # * Use a build host
        # * Garbage collect the nix store (after removing roots)
        # * Mount another disk partition and one-off build into a new store, which nix will automatically generate using
        #   command argument "--store /mnt" -> creates new substructure /mnt/nix{/,..}
        #   This will recreate (download all) the entire store from empty! To speed this up copy over data from the
        #   old store (unsure if a caching mechanism exists).
        nixosConfigurations = import ./hosts {
            inherit self lib' inputs;
        };

        # nix build .#images."<name>".config.system.build.isoImage
        images = lib'.mapAttrs' (hostname: target-host:
            lib'.nameValuePair "${hostname}-installer" (makeInstaller target-host))
            self.nixosConfigurations;
	};
}
