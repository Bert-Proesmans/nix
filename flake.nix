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
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, ... }@inputs:
    let
      # Each target we want to (cross-)compile for
      # NOTE; Cross-compiling requires additional configuration on the build host
      systems = [ "x86_64-linux" ];

      # Shorten calls to library functions;
      # lib.genAttrs == inputs.nixpkgs.lib.genAttrs
      # WARN; inputs.nixpkgs.lib =/= (nixpkgs.legacyPackages.<system> ==) pkgs.lib. The latter is 
      # the nixpkgs library, while the former is the nixpkgs _flake_ lib and this one includes 
      # the nixos library functions!
      # eg; inputs.nixpkgs.lib.nixosSystem => exists
      # eg; pkgs.lib.nixosSystem => does _not_ exist
      # eg; nixpkgs.legacyPackages.<system>.lib.nixosSystem => does _not_ exist
      lib = inputs.nixpkgs.lib.extend (_: _: self.outputs.lib);

      # Shortcut to create behaviour that abstracts over different package indexes
      eachSystem = f: lib.genAttrs systems (system: f inputs.nixpkgs.legacyPackages.${system});

      # Same shortcut, but using a customized instantiation of nixpkgs.
      #
      # NOTE; Valid nixpkgs-config attributes can be found at pkgs/toplevel/default.nix
      # REF; https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/default.nix
      eachSystemOverride = nixpkgs-config: f: lib.genAttrs systems
        (system: f (import (inputs.nixpkgs) (nixpkgs-config // { localSystem = { inherit system; }; })));
    in
    {

      # Builds an attribute set of all our library code.
      # Each library file is applied with the lib from nixpkgs.
      #
      # NOTE; This library set is extended into the nixpkgs library set later, see let .. in above.
      lib = { }
        // (import ./library/importers.nix (inputs.nixpkgs.lib))
        #// (import ./library/network.nix (inputs.nixpkgs.lib));
      ;

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

      # Build and run development shell with;
      # nix flake develop
      devShells = eachSystem (pkgs:
        let
          deployment-shell = pkgs.mkShellNoCC {
            name = "deployment";

            nativeBuildInputs = builtins.attrValues {
              # Python packages to easily execute maintenance and build tasks for this flake.
              # See tasks.py TODO
              inherit (pkgs.python3.pkgs) invoke deploykit;
            };

            packages = builtins.attrValues {
              inherit (pkgs)
                # For secret material
                sops ssh-to-age rage;
            };
          };
        in
        {
          inherit deployment-shell;

          default = pkgs.mkShellNoCC {
            name = "b-NIX development";

            # REF; https://github.com/NixOS/nixpkgs/issues/58624#issuecomment-1576860784
            inputsFrom = [ deployment-shell ];

            nativeBuildInputs = [ self.outputs.formatter.${pkgs.system} ];

            # Software directly available inside the developer shell
            packages = builtins.attrValues {
              inherit (pkgs)
                # For fun
                nyancat figlet
                # For development
                git bat;
            };

            # Open files within the visual code window
            EDITOR =
              let
                script = pkgs.writeShellApplication {
                  name = "find-editor";
                  runtimeInputs = [ pkgs.nano ];
                  text = ''
                    if ! type "code" > /dev/null; then
                      nano "$@"
                    fi

                    # Since VScode works interactively there is an instant process fork.
                    # The code calling $EDITOR is (very likely) synchronous, so we want to wait until
                    # the specific (new) editor pane has closed!
                    code --wait "$@"
                  '';
                };
              in
              lib.getExe script;
          };
        });

      # TODO
      #
      # NOTE; The type is list[attrSet[<name>, path]]
      # Nix will automatically convert the relative path into a fully qualified one during evaluation (before application).
      nixosModules = lib.filterAttrs (name: _: name != "hosts" && name != "profiles" && name != "debug") (lib.rakeLeaves ./nixosModules);

      # TODO
      nixosConfigurations =
        let
          profiles = lib.rakeLeaves ./nixosModules/profiles;

          meta-module = { ... }: {
            # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
            _file = "./flake.nix";

            # Make all custom nixos options available to the host configurations.
            imports = builtins.attrValues self.outputs.nixosModules;

            config = {
              # Flake inputs are used for importing additional nixos modules.
              # ERROR; Attributes that must be resolved during import evaluation _must_ be passed into the nixos
              # configuration through specialArgs!
              #_module.args.flake-inputs = inputs;

              _module.args.flake-overlays = self.outputs.overlays;

              _module.args.home-configurations = self.outputs.homeModules.users;

              # TODO Load facts from all nixosConfigurations and make them available to all configurations.
              _module.args.facts = { };
            };
          };
        in
        {
          development = lib.nixosSystem {
            inherit lib;
            system = null; # Deprecated, use nixpkgs.hostPlatform option
            specialArgs = {
              # Set here arguments that must be be resolvable at module import stage,
              # for all else use _module.args option.
              # See also; meta-module, above
              flake-inputs = inputs;
              inherit profiles;
            };
            modules = [
              meta-module
              ./nixosModules/hosts/development/configuration.nix
            ];
          };

          buddy = lib.nixosSystem {
            inherit lib;
            system = null; # Deprecated, use nixpkgs.hostPlatform option
            specialArgs = {
              # Set here arguments that must be be resolvable at module import stage,
              # for all else use _module.args option.
              # See also; meta-module, above
              flake-inputs = inputs;
              inherit profiles;
            };
            modules = [
              meta-module
              ./nixosModules/hosts/buddy/configuration.nix
            ];
          };

        };

      # Home manager modules are just lambda's with an attribute set as argument (arity of all nix functions is
      # always one), not a derivations. So home manager modules on their own do nothing.
      #
      # Refer to homeModules.users for the definition of each user's home configuration. Those attribute sets
      # include other modules defining more options, a tree of dependencies could be built with those sets
      # at the root (or top). This turns those modules into toplevel modules.
      #
      homeModules = (lib.rakeLeaves ./homeModules);

      # NOTE; Home modules above can be incorporated in a standalone configuration that evaluates independently
      # of nixos host configurations.
      # I'm not doing that though, since the nixos integrated approach works well for me.
      # SEE ALSO; ./home/modules/home-manager.nix


      # Set of blobs to build, can be applications or ISO's or documents (reports/config files).
      #
      # Build with; nix build
      # eg, nix build --out-link bootstrap.iso => blob bootstrap.iso, can be used to bootstrap new machines with nixos configuration
      #
      # Run with; nix run .#<binary-name>
      # eg, packages.x86_64-linux.development = self.nixosConfigurations.development.config.formats.vm-nogui => nix run .#development
      # packages = eachSystem (pkgs:
      #   let
      #     # Force the system architecture to that of the host for native virtualization (no emulation required)
      #     forced-system = pkgs.system;

      #     # Convert defined nixos hosts into installation iso's for self-installation
      #     install-host = lib.nixosSystem {
      #       # System is deprecated, it's set within the modules as nixpkgs.hostPlatform
      #       system = null;
      #       # Inject our own library functions before calling nixosSystem.
      #       # The merged attribute set will become the nixosModule argument 'lib'. 'lib' is not directly related to 'pkgs.lib', because 'pkgs'
      #       # can be set from within nixosModules. Overridable 'lib' would result in circular dependency because configuration is dependent on
      #       # lib.mkIf and similar.
      #       lib = lib;
      #       # Additional custom arguments to each nixos module
      #       specialArgs = {
      #         inherit (self.outputs.nixosModules) profiles;
      #       };
      #       # The toplevel nixos module recursively imports relevant other modules
      #       modules = commonNixosModules
      #         ++ [
      #         self.outputs.nixosModules.profiles.users
      #         self.outputs.nixosModules.profiles.remote-iso
      #         ({ lib, ... }: {
      #           networking.hostName = lib.mkForce "installer";
      #           networking.domain = lib.mkForce "alpha.proesmans.eu";

      #           # Make sure EFI store is writable because we're installing!
      #           boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

      #           # Force machine configuration to match the nix CLI build target attribute path
      #           # packages.x86_64-linux builds a x86_64-linux VM.
      #           nixpkgs.hostPlatform = lib.mkForce forced-system;
      #           # Consistent defaults while updating flake inputs.
      #           system.stateVersion = lib.mkForce "23.11";
      #         })
      #       ];
      #     };

      #     # An installer configuration for each defined nixos host
      #     specialized-install-hosts = lib.flip lib.mapAttrs' self.outputs.nixosConfigurations
      #       (hostname: _: lib.nameValuePair
      #         # Change the attribute name with iso suffix, use like this; nix build .#development-iso
      #         ("${hostname}-iso")
      #         (install-host.extendModules {
      #           modules = [
      #             ({ ... }: {
      #               # Carry the target machine configuration inside this host's store
      #               proesmans.install-script.enable = true;
      #               proesmans.install-script.host-attribute = hostname;
      #             })
      #           ];
      #         }));

      #     # A virtual machine for each defined nixos host
      #     virtual-hosts = lib.flip lib.mapAttrs' self.outputs.nixosConfigurations
      #       (hostname: configuration: lib.nameValuePair
      #         # Change the attribute name with vm suffix, use like this; nix build .#development-vm
      #         ("${hostname}-vm")
      #         (configuration.extendModules {
      #           modules = [
      #             self.outputs.nixosModules.profiles.local-vm-test
      #             ({ lib, ... }: {
      #               # Force machine configuration to match the nix CLI build target attribute path
      #               # packages.x86_64-linux builds a x86_64-linux VM.
      #               nixpkgs.hostPlatform = lib.mkForce forced-system;
      #             })
      #           ];
      #         }));

      #     # ERROR; The attribute `vm-nogui` creates a script, but not in the form of an application package.
      #     # The script is wrapped so 'nix run' can find and execute it.
      #     vm-launcher-wrapper = name: configuration: pkgs.writeShellApplication {
      #       name = "launch-wrapper-${name}";
      #       text = ''
      #         # All preparations before launching the virtual machine goes here
      #         ${configuration.config.formats.vm-nogui}
      #       '';
      #     };
      #   in
      #   (builtins.mapAttrs vm-launcher-wrapper virtual-hosts)
      #   # Specifically built installer iso's from each configuration
      #   // builtins.mapAttrs (_: system: system.config.formats.install-iso) specialized-install-hosts
      #   // {
      #     # Lightweight bootstrap machine for initiating remote deploys. This configuration doesn't carry
      #     # a target host.
      #     default = install-host.config.formats.install-iso;

      #     # NOTE; For a self-deploying development machine, use the #development-iso attribute!
      #     # eg; nix build .#development-iso
      #   });

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
      # checks = eachSystem (pkgs: lib.pipe ./checks [
      #   # Read checks folder, outputs the file structure containing tests
      #   (lib.rakeLeaves)
      #   # Flatten nested attribute sets, outputs name-value pairs on a single level
      #   (lib.flattenTree)
      #   # Keep the nix file paths
      #   (builtins.attrValues)
      #   # Import file, outputs lambdas that produce test derivations
      #   (builtins.map (file-path: (import file-path)))
      #   # Apply lambdas, outputs test derivations
      #   (builtins.map (lambda: lambda {
      #     inherit self lib pkgs commonNixosModules;
      #     inherit (self) inputs outputs;
      #   }))
      #   # Shallow merge the attribute set, results in exported checks
      #   # ERROR; Last attribute set wins in case of name conflicts (that's why fold-left)
      #   (builtins.foldl' (final: part: final // part) { /* starts with empty set */ })
      # ]);

      # Overwrite (aka patch) functionality defined by the inputs, mostly nixpkgs.
      #
      # These attributes are lambda's that don't do anything on their own. Use the `overlay`
      # options to incorporate them into your configuration.
      # eg; (nixos options) nixpkgs.overlays = self.outputs.overlays;
      #
      # See also; nixosModules.nix-system
      overlays = {
        atuin = import ./overlays/atuin;
      };
    };
}
