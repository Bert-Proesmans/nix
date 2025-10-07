{
  description = "Bert's NixOS configurations";

  # nixConfig.extra-substituters = [ ];
  # nixConfig.extra-trusted-public-keys = [ ];

  inputs = {
    nixpkgs.follows = "nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # WARN; Seems like everybody is using flake-utils, but this dependency does not bring anything
    # functional without footguns or anything we can't do ourselves.
    # It's imported to simplify/merge the input chain, but unused in this flake.
    flake-utils.url = "github:numtide/flake-utils";

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
    crowdsec.url = "git+https://codeberg.org/kampka/nix-flake-crowdsec.git";
    crowdsec.inputs.nixpkgs.follows = "nixpkgs";
    crowdsec.inputs.flake-utils.follows = "flake-utils";
  };

  outputs =
    { self, ... }:
    let
      inherit (self) inputs outputs;

      # Shorten calls to library functions;
      # lib.genAttrs == inputs.nixpkgs.lib.genAttrs
      #
      # WARN; inputs.nixpkgs.lib =/= (nixpkgs.legacyPackages.<system> ==) pkgs.lib.
      # In other words, the latter is the nixpkgs library, while the former is
      # the nixpkgs _flake_ lib and this one includes the nixos library functions!
      # eg; inputs.nixpkgs.lib.nixosSystem => exists
      # eg; pkgs.lib.nixosSystem => does _not_ exist
      # eg; nixpkgs.legacyPackages.<system>.lib.nixosSystem => does _not_ exist
      lib = inputs.nixpkgs.lib.extend (
        inputs.nixpkgs.lib.composeManyExtensions [
          (_: _: { dns = inputs.dns.lib; }) # lib from dns.nix
          (_: _: outputs.lib) # Our own lib
        ]
      );

      __forSystems = lib.genAttrs [ "x86_64-linux" ];
      __forPackages = __forSystems (system: inputs.nixpkgs.legacyPackages.${system});
      # Helper creating attribute sets for each supported system.
      eachSystem = mapFn: __forSystems (system: mapFn __forPackages.${system});
    in
    {
      # NOTE; This library set is extended into the nixpkgs library set, see let .. in above.
      lib = import ./library/all.nix { inherit lib; };

      # Format entire flake with;
      # nix fmt
      #
      formatter = eachSystem (pkgs: inputs.treefmt-nix.lib.mkWrapper pkgs ./treefmt.nix);

      # Build and run development shell with;
      # nix flake develop
      #
      # NOTE; The "default" shell will be loaded by nix-direnv on entering the repository directory.
      #
      devShells = eachSystem (pkgs: import ./devshells.nix { inherit pkgs lib; });

      # Overwrite (aka patch) declarative configuration, most often build recipes from nixpkgs.
      #
      # These attributes are lambda's that don't do anything on their own. Use the `overlay` options to incorporate them into
      # your configuration.
      # eg; (nixos options) nixpkgs.overlays = builtins.attrValues self.outputs.overlays;
      # eg; (nix extensible attr set) _ = lib.extends (lib.composeManyExtensions (builtins.attrValues self.outputs.overlays));
      #
      # See also; self.outputs.nixosModules.nix-system
      #
      overlays = {
        outline = import ./overlays/outline/default.nix;
        haproxy-build-fix = _final: previous: {
          # The Haproxy recipe currently applies fixes for a CVE twice.
          # TODO; Remove the overlay once recipe has been fixed.
          # REF; https://github.com/NixOS/nixpkgs/pull/448677#issuecomment-3378349488
          haproxy = previous.haproxy.overrideAttrs (old: {
            patches = [ ];
          });
        };
        # example = final: previous: {
        #   hello = previous.hello.overrideAttrs (old: {
        #     version = "${old.version}-superior";
        #   });
        # };
      };

      # NixOS modules are anonymous lambda functions with an attribute set as the first argument (arity of all nix functions is
      # always one). NixOS modules on their own do nothing, but need to be composed into a nixosConfiguration.
      #
      # Refer to the filepath ./nixosConfigurations for the definition/configuration of each host machine. Starting from
      # the configuration.nix file, other nixos module files are imported. The collective set of all imported modules is
      # turned into the host configuration.
      # Because the configuration.nix file is typically imported first, it's called the toplevel (nixos) module.
      #
      # NOTE; The type of this value is attrSet[<name>, <path>]
      # eg {filesystem = ./nixosModules/filesystem.nix;}
      #
      # NOTE; Paths are a value type in nix, and nix will resolve these paths to their fixed store path
      # (eg /nix/store/aaabbbcccdddd/nixosModules/filesystem.nix) during evaluation (when derivations files are created).
      # The prefix in the resulting path (/aaabbbcccddd) comes from the outPath attribute of this flake.
      #
      nixosModules = outputs.lib.rakeLeaves ./nixosModules;

      # Home (manager) modules share the same evaluation mechanism as NixOS modules and are structurally the same. Home modules
      # have different option declarations, that is the only difference.
      #
      # SEEALSO; self.outputs.nixosModules
      #
      homeModules = outputs.lib.rakeLeaves ./homeModules;

      # Print and externall process host information with;
      # nix eval --json .#facts
      #
      # TODO; Examples of using this data
      #
      facts =
        let
          factModules = outputs.lib.rakeFacts ./nixosConfigurations;
          evaluation = lib.evalModules {
            modules = [
              ./nixosModules/facts.nix
              ({
                proesmans.facts = factModules;
              })
            ];
          };
        in
        evaluation.config.proesmans.facts;

      # nixosConfigurations are the full interconnected configuration data to build a host machine. This collection of data resolves
      # to an output (of any kind) depending on the attribute you ask it to build. These attributes are under the ".config" set
      # because that is the standardized attribute path for evaluated nixos module configurations.
      #
      # Build the disk contents to run a machine with;
      # nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel
      #
      # NOTE; Deployment of hosts in this flake is handled by the "invoke" framework, the deploy task executes "nixos-anywhere" to
      # prepare the host hardware and install the NixOS distribution on the target.
      # SEEALSO; self.outputs.devShells.default
      # SEEALSO; ./tasks.py file
      #
      #
      # Deploy with nixos-anywhere;
      # nix run github:nix-community/nixos-anywhere -- --flake .#<hostname (attribute-name within nixosConfigurations)> <user>@<ip address>
      # NOTE; nixos-anywhere will automatically look under #nixosConfigurations for the provided attribute name,
      # "nixosConfigurations" can thus be omitted from the command line invocation.
      # NOTE; <user> must be root or have passwordless sudo on the target host machine, most often the target is booted from the installer iso.
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine.
      #
      #
      # Update with; nixos-rebuild switch --flake .#<hostname> --target-host <user>@<ip address>
      # NOTE; nixos-anywhere will automatically look under #nixosConfigurations for the provided attribute name,
      # "nixosConfigurations" can thus be omitted from the command line invocation.
      # NOTE; <user> must be root or have passwordless sudo on the target host machine, most often the target is booted from the installer iso.
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine.
      #
      #
      # NOTE; Optimizations like --use-substituters and caching can be used to speed up the building/install/update process.
      # Using this optimization depends on properties of the build-host and the target-host.
      # eg use it when the upload speed of the build-host is slower than the download speed of the target-host.
      #
      nixosConfigurations = import ./nixosConfigurations/all.nix {
        inherit lib;
        flake = self;
      };
      # no homeConfigurations

      # Build a bootstrap image using;
      # nix build
      #
      # Build vsock-proxy, or any other program by attribute name using;
      # nix build .#vsock-proxy
      #
      # Collection of derivations that build concrete binary file packages.
      # All attributes this flake defines lead to creating some concrete file. The semantics for "packages" is binaries, but could
      # be anything really.
      #
      packages = eachSystem (
        pkgs:
        # NOTE; lib.fix creates a recursive scope, sort of like let in {} with nix lazy evaluation.
        # ERROR; Don't use lib.{new,create}Scope because those inject additional attributes that 'nix flake check'
        # doesn't like!
        lib.fix (
          final:
          let
            # NOTE; Create our own callPackage function with our recursive scope, this function
            # will apply the necessary arguments to each package recipe.
            callPackage = pkgs.newScope (
              final
              // {
                # HERE; Add more custom package arguments. Only items that are _NOT_ derivations!

                flake = self;
                nixosLib = lib;
              }
            );
          in
          {
            # HERE; Add aliasses and/or overrides.

            default = final.bootstrap;
          }
          // lib.packagesFromDirectoryRecursive {
            inherit callPackage;
            # NOTE; Imports and processes files named "package.nix".
            directory = ./packages;
          }
        )
      );

      # Execute and validate tests against this flake configuration;
      # nix-fast-build
      # [BROKEN; keeps running out of memory, use nix-fast-build] nix flake check --no-eval-cache --keep-going
      #
      # WARN; "nix-eval-jobs" only _evaluates_ nix code and derivations, nothing concrete is build! During Continuous Integration (CI)
      # this could be enough, otherwise also _build your derivations_.
      # NixOS tests run during build (which is kinda weird but okay..), unless the runInteractive attribute is evaluated and built.
      #
      checks = eachSystem (_: {
        # example = pkgs.testers.runNixOSTest {
        #   name = "example";
        #   nodes = { };
        #   testScript = ''
        #     # TODO
        #   '';
        # };
      });

      # Build everything defined (basically similar to nix flake check);
      # (interactive) nix-fast-build --flake .#hydraJobs
      # (noninteractive/CI] nix-fast-build --no-nom --skip-cached --flake ".#hydraJobs.$(nix eval --raw --impure --expr builtins.currentSystem)"
      #
      # NOTE; There is no schema for the hydraJobs attribute set, but the trend of "packages"/"checks" is followed for easy
      # filtering on target host system type.
      #
      hydraJobs =
        eachSystem (pkgs: {
          recurseForDerivations = true;
          formatter = outputs.formatter.${pkgs.system};
          devShells = outputs.devShells.${pkgs.system};
          packages = outputs.packages.${pkgs.system};
          checks = outputs.checks.${pkgs.system};
        })
        // {
          no-system.recurseForDerivations = true;
          no-system.nixosConfigurations = lib.mapAttrs (
            _: v: v.config.system.build.toplevel
          ) outputs.nixosConfigurations;
        };
    };
}
