{
  description = "Bert Proesmans's NixOS configuration";

  inputs = {
    nixpkgs.follows = "nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
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

      profiles-nixos = lib.rakeLeaves ./nixosModules/profiles;
    in
    {

      # Builds an attribute set of all our library code.
      # Each library file is applied with the lib from nixpkgs.
      #
      # NOTE; This library set is extended into the nixpkgs library set later, see let .. in above.
      lib = { }
        // (import ./library/importers.nix (inputs.nixpkgs.lib))
        // (import ./library/network.nix (inputs.nixpkgs.lib));

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
                sops ssh-to-age rage
                # For deploying new hosts
                nixos-anywhere
                ;
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
          meta-module = { ... }: {
            # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
            _file = ./flake.nix;

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
              profiles = profiles-nixos;
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
              profiles = profiles-nixos;
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

      # TODO
      packages = eachSystem (pkgs:
        let
          forced-system = pkgs.system;

          # NOTE; Minimal installer based host to get new hosts up and running
          bootstrap = lib.nixosSystem {
            system = null;
            lib = lib;
            specialArgs = {
              flake-inputs = inputs;
              profiles = profiles-nixos;
            };
            modules = [
              ({ lib, profiles, modulesPath, config, ... }: {
                # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
                _file = ./flake.nix;

                imports = [
                  "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
                  profiles.remote-iso
                  # NOTE; Explicitly not importing the nixosModules to keep configuration minimal!
                ];

                config = {
                  networking.hostName = lib.mkForce "installer";
                  networking.domain = lib.mkForce "alpha.proesmans.eu";

                  # Fallback quickly if substituters are not available.
                  nix.settings.connect-timeout = lib.mkForce 5;
                  # Enable flakes
                  nix.settings.experimental-features = [ "nix-command" "flakes" "repl-flake" ];
                  # The default at 10 is rarely enough.
                  nix.settings.log-lines = lib.mkForce 25;
                  # Dirty git repo warnings become tiresome really quickly...
                  nix.settings.warn-dirty = lib.mkForce false;

                  # Faster and (almost) equally as good compression
                  isoImage.squashfsCompression = lib.mkForce "zstd -Xcompression-level 15";
                  # Ensure sshd starts at boot
                  systemd.services.sshd.wantedBy = [ "multi-user.target" ];
                  # No Wifi
                  networking.wireless.enable = lib.mkForce false;
                  # No docs
                  documentation.enable = lib.mkForce false;
                  documentation.nixos.enable = lib.mkForce false;

                  # Drop ~400MB firmware blobs from nix/store, but this will make the host not boot on bare-metal!
                  # hardware.enableRedistributableFirmware = lib.mkForce false;
                  # ERROR; The mkForce is required to _reset_ the lists to empty! While the default
                  # behaviour is to make a union of all list components!
                  # No GCC toolchain
                  system.extraDependencies = lib.mkForce [ ];
                  # Remove default packages not required for a bootable system
                  environment.defaultPackages = lib.mkForce [ ];

                  nixpkgs.hostPlatform = lib.mkForce forced-system;
                  system.stateVersion = lib.mkForce config.system.nixos.version;
                };
              })
            ];
          };
        in
        {
          # NOTE; You can find the generated iso file at ./result/iso/*.iso
          default = bootstrap.config.system.build.isoImage;

          development-iso = (bootstrap.extendModules {
            modules = [
              # NOTE; Explicitly not importing the nixosModules to keep configuration minimal!
              ({ profiles, ... }: {
                # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
                _file = ./flake.nix;
                key = "${./flake.nix}?development-iso";

                imports = [ profiles.development-bootstrap ];

                config = {
                  isoImage.storeContents = [
                    # NOTE; The development machine toplevel derivation is included as a balancing act;
                    # Bigger ISO image size <-> 
                    #     + Less downloading 
                    #     + Less RAM usage (nix/store is kept in RAM on live boots!)
                    self.outputs.nixosConfigurations.development.config.system.build.toplevel
                  ];
                };
              })
            ];
          }).config.system.build.isoImage;
        }
      );

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
      # eg; (nix extensible attr set) _ = lib.extends (lib.composeManyExtensions (builtins.attrValues self.outputs.overlays));
      #
      # See also; nixosModules.nix-system
      overlays = {
        atuin = import ./overlays/atuin;
      };
    };
}
