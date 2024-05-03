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
              curry-arguments = { inherit (self) inputs outputs; };
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

      # Set with named binaries.
      # Run with; nix run .#<binary-name>
      # eg, packages.x86_64-linux.bootstrap = self.nixosConfigurations.bootstrap.config.formats.vm => nix run .#bootstrap-vm
      packages = eachSystem (pkgs:
        let
          # Force the system architecture to that of the host for native virtualization (no emulation required)
          forced-system = pkgs.system;
          systems = lib.flip builtins.mapAttrs self.outputs.nixosConfigurations
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
          wrap-launcher = name: configuration: pkgs.writeShellApplication {
            name = "launch-wrapper-${name}";
            text = ''
              # All preparations before launching the virtual machine goes here
              ${configuration.config.formats.vm-nogui}
            '';
          };
        in
        (builtins.mapAttrs wrap-launcher systems) // {
          # Build machine 'development' for bootstrapping new hosts.
          # Function 'extendModules' on attributes set from nixosSystem is not used because I want to
          # disable stuff. 'extendModules' works by creating a wrapper around the already configured machine.
          default = (self.outputs.nixosConfigurations.development.extendModules {
            modules = [
              ({ pkgs, lib, config, ... }: {
                # Force machine configuration to match the nix CLI build target attribute path
                # packages.x86_64-linux builds a x86_64-linux VM.
                nixpkgs.hostPlatform = lib.mkForce forced-system;
                # Make sure EFI store is writable because we're installing!
                boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
                # Append all user ssh keys to the root user
                users.users.root.openssh.authorizedKeys.keys = lib.lists.flatten
                  # Flatten all public keys into a single list
                  (lib.attrsets.mapAttrsToList (_: user: user.openssh.authorizedKeys.keys)
                    # For each user with attribute isNormalUser
                    (lib.attrsets.filterAttrs (_: user: user.isNormalUser) config.users.users));

                # 90+ percentage of the cases I will need this image for virtual machine bootstrapping
                # ERROR; Dropping the firmware will make this configuration unbootable on real metal!
                hardware.enableRedistributableFirmware = lib.mkForce false;
                # Don't store the repo files, only keep a reference for downloading later
                proesmans.nix.references-on-disk = lib.mkForce false;
                # Disable the vscode server patch because it's large as fuck
                services.vscode-server.enable = lib.mkForce false;

                # Nix pointers for the install script to work
                nix.nixPath = [ "/etc/nix/path" ];
                # NOTE; This flake (the value of variable 'self') is copied by-value into the bootstrap image.
                # AKA All files in this repository are copied into the resulting build.
                environment.etc."nix/path/my-flake".source = self;
                nix.registry.my-flake.flake = self;

                services.getty.helpLine = lib.mkAfter ''
                  This machine has been configured with an installer script, run 'install-system' to (ya-know) install the system ☝️
                '';

                # Provide an installer script that performs all installation steps automagically
                environment.systemPackages = [
                  (
                    let
                      install-system = pkgs.writeShellApplication {
                        name = "inner-install-system";
                        runtimeInputs = [ pkgs.nix pkgs.nixos-install-tools ]; # Cannot use pkgs.sudo, for workaround see 'export PATH' below
                        text = ''
                          # Script that formats disks, and mounts partitions, and installs data from the development machine
                          # NOTE; 'my-flake' is a flake reference, installed through nixos option nix.registry (see above)
                          # my-flake is a reference to this flake

                          # Fun fact; Sudo does not work in a pure shell. It fails with error 'sudo must be owned by uid 0 and have the setuid bit set'
                          # Nixos has someting called security wrappers (nixos option security.wrapper) which perform additional 
                          # setup during the shell init, wrapping sudo and other security related binaries.
                          # The export below pulls in all programs that were wrapped by the system configuration. Impure, sadly..
                          export PATH="${config.security.wrapperDir}:$PATH"
                        
                          echo "# Install wrapper started"

                          pushd "$(mktemp -d -p "/tmp" install-XXXXXX)"
                          TEMPD=$(pwd)
                          trap "exit 1" HUP INT PIPE QUIT TERM
                          trap "popd" EXIT
                          echo "# Changed into temporary directory $TEMPD"

                          nix build --out-link disko-script my-flake#nixosConfigurations.development.config.system.build.diskoScript
                            echo "# Built disk format+mounting script"
                          nix build --out-link system-closure my-flake#nixosConfigurations.development.config.system.build.toplevel
                            echo "# Built system configuration"

                          sudo ./disko-script
                            echo "# Disks formatted"
                          # NOTE; '0' as value for cores means "use all available cores"
                          sudo nixos-install --no-channel-copy --no-root-password --max-jobs 4 --cores 0 --system "$(readlink ./system-closure)"
                            echo "# System installed"

                          echo "# Script done"
                        '';
                      };
                    in
                    # Wrapper script for capturing the output of the actual installation progress
                    pkgs.writeShellApplication {
                      name = "install-system";
                      runtimeInputs = [ install-system ];
                      text = ''
                        # Create a temporary log file with a unique name
                        log_file="$(mktemp -t install-system.XXXXXX.log)"

                        # Execute the wrapped script, capturing both stdout and stderr
                        "${lib.getExe install-system}" 2>&1 | tee "$log_file"

                        echo "Execution log is saved at: $log_file"
                      '';
                    }
                  )
                ];
              }
              )
            ];
          }).config.formats.install-iso;
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
