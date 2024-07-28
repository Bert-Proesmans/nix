{
  description = "Bert Proesmans's NixOS configuration";

  inputs = {
    nixpkgs.follows = "nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
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
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
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

      # Small tool to iterate over each target, but use a customized instantiation of nixpkgs.
      # NOTE; The nixpkgs-config parameter destructuring is purely for documentation. The entire callflow chain
      # of nixpkgs ignores unused arguments and typos _will_ cause invisibly broken functionality!
      eachSystemOverride = { ... }@nixpkgs-config: f:
        lib.genAttrs [ "x86_64-linux" ]
          (system: f (import (inputs.nixpkgs) (nixpkgs-config // { localSystem = { inherit system; }; })));

      # Automatically include all nixos modules that are not part of the hosts collection.
      # The (nixosModules.)hosts attribute set holds one config per machine, and we turn each into a nixosSystem derivation.
      # NOTE; That one nixos module defining the host configuration is also called a 'toplevel module'.
      commonNixosModules =
        let
          unwanted-filtering = name: _: name != "hosts" && name != "profiles";
        in
        lib.attrValues (lib.filterAttrs unwanted-filtering self.outputs.nixosModules);
    in
    {
      # Load our custom functionality and variable types, without using 'lib' because that would result in
      # a circular dependency.
      # 1. Import each path, resulting in multiple lambdas
      # 2. Apply the final library on every lambda, resulting in multiple attribute sets
      # 3. Shallow merge each attribute set, into lib
      lib =
        let
          # Taken from lib.pipe, for code clarity
          pipe = builtins.foldl' (x: f: f x);
        in
        pipe [
          ./library/facts.nix
          # Add library files here
          ./library/importers.nix
          ./library/network.nix
        ] [
          # Import each library path, results in lambdas
          (builtins.map (file-path: import file-path))
          # Apply the final library to every lambda, results in attribute sets
          (builtins.map (lambda: lambda /* `lib` is from `let .. in` above */ lib))
          # Shallow merge the attribute set, results in exported lib. 
          # ERROR; Last attribute set wins in case of name conflicts (that's why fold-left)
          (builtins.foldl' (final: part: final // part) { /* starts with empty set */ })
        ];

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
          programs.shfmt = {
            enable = true;
            # Setting option to 'null' configures formatter to follow .editorconfig
            indent_size = null;
          };
          # Python linting/formatting
          programs.ruff.check = true;
          programs.ruff.format = true;
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
        }).config.build.wrapper);

      # Build development shell with;
      # nix flake develop
      devShells = eachSystemOverride
        {
          config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
            "vault"
          ];
        }
        (pkgs: {
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
            packages = builtins.attrValues {
              inherit (pkgs)
                # For fun
                nyancat figlet
                # For development
                git bat
                # For secret material
                sops ssh-to-age rage;
            };
          };
        });

      # nixOS modules are just lambda's with an attribute set as argument (arity of all nix functions is
      # always one), not a derivations. So nixOS modules on their own do nothing.
      #
      # Refer to nixosModules.hosts for the definition/configuration of each machine. Those attribute sets
      # include other modules defining more options, a tree of dependencies could be built with those sets
      # at the root (or top). This turns those modules into toplevel modules.
      #
      # I do not want to add argument 'inputs' (as in flake inputs) into the nixos modules, because of
      # seperating concerns.
      # That means some of the lambda's need to be curried (arity of all nix lambda's is ALWAY one (1)).
      # The mapping function below checks if the lambda must be curried (aka it's not a nixos module)
      # and applies, otherwise the lambda is passed through as is.
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
              curry-arguments = {
                inherit (self) inputs outputs;
                inherit commonNixosModules;
              };
              # We want to partially apply, for the technical challenge!
              curry-intersect = builtins.intersectAttrs lambda-arguments curry-arguments;
              should-curry =
                # If there is at least one argument to apply
                (builtins.length (builtins.attrNames curry-intersect)) > 0
                # If the intersection is a full overlap with the requested arguments
                && (builtins.attrNames lambda-arguments) == (builtins.attrNames curry-intersect);
            in
            (if should-curry then (lambda curry-intersect) else lambda);
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
            specialArgs = {
              inherit (self.outputs.nixosModules) profiles;
            };
            # The toplevel nixos module recursively imports relevant other modules
            modules = commonNixosModules ++ [ toplevel-module ];
          })
        self.nixosModules.hosts;

      # Home manager modules are just lambda's with an attribute set as argument (arity of all nix functions is
      # always one), not a derivations. So home manager modules on their own do nothing.
      #
      # Refer to homeModules.users for the definition of each user's home configuration. Those attribute sets
      # include other modules defining more options, a tree of dependencies could be built with those sets
      # at the root (or top). This turns those modules into toplevel modules.
      #
      homeModules = (lib.rakeLeaves ./homeModules);

      # Update home directories with; nix run github:nix-community/home-manager -- switch
      #
      # NOTE; This is using home-manager in standalone mode. This is useful for getting a consistent user configuration
      # on machines that are not NixOS.
      # All machines defined in this flake have home-manager built into the machine configuration. The home-configuration
      # on NixOS machines will be updated through nixos-rebuild.
      #
      # Testing of home-configurations is not built into this flake. I have built a single basic integration test for the
      # user bert-proesmans, see file ./checks/home-tests.nix.
      #
      # DISABLED; Standalone home-manager configuration is unused and untested. The homeModules are integrated in 
      # "nixos-integrated-configuration" mode.
      # homeConfigurations = eachSystem (pkgs: lib.mapAttrs
      #   (user-reference: toplevel-module: inputs.home-manager.lib.homeManagerConfiguration {
      #     # Home-manager is system agnostic, its options reference packages from the provided attribute set that has been
      #     # specialized for a specific given system. 
      #     inherit pkgs;
      #     # The toplevel module will include other modules if necessary.
      #     modules = [
      #       toplevel-module
      #       ({ lib, config, ... }: {
      #         # Home-manager requires home.username and home.homeDirectory to be set, but it can/will only set 
      #         # those options for nixos module config. The toplevel home-modules are _also_ used in standalone mode
      #         # (next to integrated into nixos -mode) where an error will occur if these options are missing.
      #         home.username = lib.mkDefault user-reference;
      #         home.homeDirectory = lib.mkDefault "/home/${user-reference}";
      #       })
      #     ];
      #   })
      #   self.homeModules.users);

      # Set of blobs to build, can be applications or ISO's or documents (reports/config files).
      #
      # Build with; nix build
      # eg, nix build --out-link bootstrap.iso => blob bootstrap.iso, can be used to bootstrap new machines with nixos configuration
      #
      # Run with; nix run .#<binary-name>
      # eg, packages.x86_64-linux.development = self.nixosConfigurations.development.config.formats.vm-nogui => nix run .#development
      packages = eachSystem (pkgs:
        let
          # Force the system architecture to that of the host for native virtualization (no emulation required)
          forced-system = pkgs.system;

          # Convert defined nixos hosts into installation iso's for self-installation
          install-host = lib.nixosSystem {
            # System is deprecated, it's set within the modules as nixpkgs.hostPlatform
            system = null;
            # Inject our own library functions before calling nixosSystem.
            # The merged attribute set will become the nixosModule argument 'lib'. 'lib' is not directly related to 'pkgs.lib', because 'pkgs'
            # can be set from within nixosModules. Overridable 'lib' would result in circular dependency because configuration is dependent on
            # lib.mkIf and similar.
            lib = lib;
            # Additional custom arguments to each nixos module
            specialArgs = {
              inherit (self.outputs.nixosModules) profiles;
            };
            # The toplevel nixos module recursively imports relevant other modules
            modules = commonNixosModules
              ++ [
              self.outputs.nixosModules.profiles.users
              self.outputs.nixosModules.profiles.remote-iso
              ({ lib, ... }: {
                networking.hostName = lib.mkForce "alpha";
                networking.domain = lib.mkForce "installer.proesmans.eu";

                # Make sure EFI store is writable because we're installing!
                boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

                # Force machine configuration to match the nix CLI build target attribute path
                # packages.x86_64-linux builds a x86_64-linux VM.
                nixpkgs.hostPlatform = lib.mkForce forced-system;
                # Consistent defaults while updating flake inputs.
                system.stateVersion = lib.mkForce "23.11";
              })
            ];
          };

          # An installer configuration for each defined nixos host
          specialized-install-hosts = lib.flip lib.mapAttrs' self.outputs.nixosConfigurations
            (hostname: _: lib.nameValuePair
              # Change the attribute name with iso suffix, use like this; nix build .#development-iso
              ("${hostname}-iso")
              (install-host.extendModules {
                modules = [
                  ({ ... }: {
                    # Carry the target machine configuration inside this host's store
                    proesmans.install-script.enable = true;
                    proesmans.install-script.host-attribute = hostname;
                  })
                ];
              }));

          # A virtual machine for each defined nixos host
          virtual-hosts = lib.flip builtins.mapAttrs self.outputs.nixosConfigurations
            (_name: configuration: configuration.extendModules {
              modules = [
                self.outputs.nixosModules.profiles.local-vm-test
                ({ lib, ... }: {
                  # Force machine configuration to match the nix CLI build target attribute path
                  # packages.x86_64-linux builds a x86_64-linux VM.
                  nixpkgs.hostPlatform = lib.mkForce forced-system;
                })
              ];
            });

          # ERROR; The attribute `vm-nogui` creates a script, but not in the form of an application package.
          # The script is wrapped so 'nix run' can find and execute it.
          vm-launcher-wrapper = name: configuration: pkgs.writeShellApplication {
            name = "launch-wrapper-${name}";
            text = ''
              # All preparations before launching the virtual machine goes here
              ${configuration.config.formats.vm-nogui}
            '';
          };
        in
        (builtins.mapAttrs vm-launcher-wrapper virtual-hosts)
        # Specifically built installer iso's from each configuration
        // builtins.mapAttrs (_: system: system.config.formats.install-iso) specialized-install-hosts
        // {
          # Lightweight bootstrap machine for initiating remote deploys. This configuration doesn't carry
          # a target host.
          #default = install-host.config.formats.install-iso;

          # Development machine as a package
          default = specialized-install-hosts.development-iso.config.formats.install-iso;
        });

      # Verify flake configurations with;
      # nix flake check --no-eval-cache
      #
      # `nix flake check` by default evaluates and builds derivations (if applicable) of common flake schema outputs.
      # It's not necessary to explicitly add packages, devshells, nixosconfigurations (build.toplevel attribute) to this attribute set.
      # Add custom derivations, like nixos-tests or custom format outputs of nixosSystem, to this attribute set for
      # automated validation through a CLI-oneliner.
      #
      # Test individual machine configurations with;
      # nix build .#checks.<system>.<machine-name>-test --no-eval-cache --print-build-logs
      # eg, nix build .#checks.x86_64-linux.bootstrap-test --no-eval-cache --print-build-logs
      #
      # REF; https://nixos.org/manual/nixos/stable/#sec-running-nixos-tests-interactively
      # You can test interactively with;
      # nix build .#checks.<system>.<machine-name>-test.driverInteractive --no-eval-cache && ./result/bin/nixos-test-driver
      # This will drop you in a python shell to control your machines. Type start_all() launch all test nodes,
      # follow up by machine.shell_interact() to drop into a shell on the node "machine".
      checks = eachSystem (pkgs: lib.pipe ./checks [
        # Read checks folder, outputs the file structure containing tests
        (lib.rakeLeaves)
        # Flatten nested attribute sets, outputs name-value pairs on a single level
        (lib.flattenTree)
        # Keep the nix file paths
        (builtins.attrValues)
        # Import file, outputs lambdas that produce test derivations
        (builtins.map (file-path: (import file-path)))
        # Apply lambdas, outputs test derivations
        (builtins.map (lambda: lambda {
          inherit self lib pkgs commonNixosModules;
          inherit (self) inputs outputs;
        }))
        # Shallow merge the attribute set, results in exported checks
        # ERROR; Last attribute set wins in case of name conflicts (that's why fold-left)
        (builtins.foldl' (final: part: final // part) { /* starts with empty set */ })
      ]);

      # Overwrite (aka patch) functionality defined by the inputs, mostly nixpkgs.
      #
      # These attributes are lambda's that don't do anything on their own. Use the `overlay`
      # options to incorporate them into your configuration.
      # eg; (nixos options) nixpkgs.overlays = self.outputs.overlays;
      #
      # See also; nixosModules.nix-system
      overlays = builtins.mapAttrs (_: file-path: (import file-path)) (lib.rakeLeaves ./overlays);
    };
}
