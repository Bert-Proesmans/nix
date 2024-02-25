{
  description = "Bert Proesmans's NixOS configuration";

  inputs = {
    nixpkgs.follows = "nixos-unstable";
    nixos-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, ... }@inputs:
    let
      # Shorten calls to library functions;
      # lib.genAttrs == inputs.nixpkgs.lib.genAttrs
      # WARN; inputs.nixpkgs.lib =/= (nixpkgs.legacyPackages.<system> ==) pkgs.lib. The latter is 
      # the nixpkgs library, while the former is the nixpkgs _flake_ lib and this one includes 
      # the nixos library functions!
      # eg; (nixpkgs.legacyPackages.<system> or pkgs).lib.nixosSystem => doesn't exist
      # eg; inputs.nixpkgs.lib.nixosSystem => exists
      lib = inputs.nixpkgs.lib.extend (_: _: self.outputs.lib);

      # Small tool to iterate over each target we want to (cross-)compile for
      eachSystem = f:
        lib.genAttrs [ "x86_64-linux" ]
          (system: f inputs.nixpkgs.legacyPackages.${system});

      # Automatically include all nixos modules that are not part of the hosts collection.
      # The (nixosModules.)hosts attribute set holds one config per machine, and we turn each into a nixosSystem derivation.
      # NOTE; That one nixos module defining the host configuration is also called a 'toplevel module'.
      commonNixosModules =
        let
          not-toplevel = name: _: name != "hosts";
        in
        lib.attrValues (lib.filterAttrs not-toplevel self.outputs.nixosModules);
    in
    {
      # Load our custom functionality and variable types, without using 'lib' because that would result in
      # a circular dependency.
      # 1. Import each path, resulting in multiple lambdas
      # 2. Apply the final library on every lambda, resulting in multiple attribute sets
      # 3. Shallow merge each attribute set, into lib
      lib = builtins.foldl' (acc: set: acc // set) { }
        (builtins.map (lib-path: (import lib-path) lib) [
          ./library/importers.nix
          ./library/network.nix
        ]);

      # Format entire flake with;
      # nix fmt
      #
      # REF; https://github.com/Mic92/dotfiles/blob/0cf2fe94c553a5801cf47624e44b2b6d145c1aa3/devshell/flake-module.nix
      #
      # TreeFMT is built to be used with "flake-parts", but we're building the flake from scratch on this one! 
      #
      formatter = eachSystem (pkgs:
        (inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          programs.nixpkgs-fmt.enable = true;
          # Nix cleanup of dead code
          programs.deadnix.enable = true;
          programs.shellcheck.enable = true;
          # Python linting/formatting
          programs.ruff.enable = true;
          # Python static typing checker
          programs.mypy = {
            enable = true;
            directories = {
              "tasks" = {
                directory = ".";
                modules = [ ];
                files = [ "**/tasks.py" ];
                extraPythonPackages =
                  [ pkgs.python3.pkgs.deploykit pkgs.python3.pkgs.invoke ];
              };
            };
          };

          # Run ruff linter and formatter, fixing all fixable issues
          settings.formatter.ruff.options = [ "--fix" ];
        }).config.build.wrapper);

      # Build development shell with;
      # nix flake develop
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          name = "b-NIX development";

          # REF; https://github.com/NixOS/nixpkgs/issues/58624#issuecomment-1576860784
          inputsFrom = [ ];

          nativeBuildInputs = [ self.outputs.formatter.${pkgs.system} ]
            ++ builtins.attrValues {
            # Python packages to easily execute maintenance and build tasks for this flake.
            # See tasks.py TODO
            inherit (pkgs.python3.pkgs) invoke deploykit;
          };

          # Software directly available inside the developer shell
          packages = builtins.attrValues { inherit (pkgs) nyancat git; };
        };
      });

      # nixOS modules are just lambda's with an attribute set as first argument, not a derivations.
      # So nixOS modules on their own do nothing.
      #
      # I do not want to add argument 'inputs' (as in flake inputs) into the nixos modules, because of
      # seperating concerns.
      # That means some of the lambda's need to be curried. The mapping function below checks
      # if the lambda must be curried (aka it's not a nixos module) and applies, otherwise 
      # the lambda is passed through as is.
      #
      nixosModules =
        let
          process-item = _: item:
            # WARN; Recursively descend into attribute sets
            if (builtins.isAttrs item) then (builtins.mapAttrs process-item item)
            else if (builtins.isFunction item) then (apply-curry-if-required item)
            else if (builtins.isPath item) then (apply-curry-if-required (import item))
            else throw "Huh, haven't seen that type of item before: ${toString item}";

          apply-curry-if-required = lambda:
            let
              lambda-arguments = builtins.functionArgs lambda;
              curry-arguments = { inherit inputs; };
              # If we wanted to partially apply, intersection would be necessary.
              # curry-intersect = builtins.intersectAttrs lambda-arguments curry-arguments;
              # NOTE; Check if the lambda wants specifically '{inputs}'.
              should-curry = (builtins.attrNames lambda-arguments)
                == (builtins.attrNames curry-arguments);
            in
            (if should-curry then (lambda curry-arguments) else lambda);
        in
        builtins.mapAttrs process-item (lib.rakeLeaves ./nixosModules);

      # Test with; nix run .#<machine-name>-vm
      # WARN; It's not always necessary but recommended to overwrite the network config for eth0 to DHCP
      # WARN; It's not always necessary but recommended to create a test user for cli login
      # NOTE; The wrapper builds the target .#nixosConfigurations.<machine-name>.config.formats.vm-nogui which
      # is similar to #nixosConfigurations.<machine-name>.config.system.build.vm.
      #
      # Deploy with nixos-anywhere; nix run github:nix-community/nixos-anywhere -- --flake .#<machine-name (property of nixosConfigurations)> <user>@<ip address>
      # NOTE; nixos-anywhere will automatically look under #nixosConfigurations so that property component can be ommited from the command line
      # NOTE; <user> must be root or have passwordless sudo
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
      #
      # Update with; nixos-rebuild switch --flake .#<machine-name> --target-host <user>@<ip address>
      # NOTE; nixos-rebuild will automatically look under #nixosConfigurations so that property component can be ommited from the command line
      # NOTE; <user> must be root or have passwordless sudo
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
      #
      # NOTE; Optimizations like --use-substituters and caching can be used to speed up the building/install/update process. This depends on the conditions of the build-host and target-host
      #
      nixosConfigurations = lib.mapAttrs
        (_name: toplevel-module: lib.nixosSystem
          {
            # System is deprecated, it's set within the modules as nixpkgs.hostPlatform
            system = null;
            # Inject our own library functions before calling nixosSystem.
            # The merged attribute set will become the nixosModule argument 'lib'. 'lib' is not directly related to 'pkgs.lib', because 'pkgs'
            # can be set from within nixosModules. Overridable 'lib' would result in circular dependency because configuration is dependent on
            # lib.mkIf and similar.
            lib = lib;
            # Additional custom arguments to each nixos module
            specialArgs = { };
            # The toplevel nixos module recursively imports relevant other modules
            modules = commonNixosModules ++ [ toplevel-module ];
          })
        self.nixosModules.hosts;

      # Test flake outputs with;
      # nix flake check
      #
      # `nix flake check` by default evaluates and builds derivations if applicable of common flake schema outputs.
      # It's not necessary to explicitly add packages, devshells, nixosconfigurations (build.toplevel attribute) to this attribute set.
      # Add custom derivations, like nixos-tests or custom format outputs of nixosSystem, to this attribute set for
      # automated validation through a CLI-oneliner.
      #
      checks = eachSystem (_pkgs:
        {
          # EMPTY
        });
    };
}
