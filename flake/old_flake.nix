rec {
  description = "Bert Proesmans's NixOS configuration";

  inputs = {
    nixpkgs.follows = "nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
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
    dns.url = "github:nix-community/dns.nix";
    dns.inputs.nixpkgs.follows = "nixpkgs";
    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Parts of this flake have existing artifacts in these binary caches. The items below are hints towards
  # consumers of this flake.
  #
  # The nix cli will automatically ask you to trust/distrust these hints. You must be a user account that is
  # added to the nix configuration "trusted-users" array to be able to make use of these substituters.
  nixConfig.extra-substituters = [
    "https://nix-community.cachix.org"
    "https://microvm.cachix.org"
  ];
  nixConfig.extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
  ];

  outputs = { self, ... }@args:
    let
      flake = self // {
        # NOTE; The resolved input sources, which match the traditional 'inputs' in documentation and guides,
        # are automatically inserted into the flake attribute "inputs".
        # SUPERFLUOUS; inputs = args;

        # The original input metadata can be reused when building the nix registry configuration of
        # the hosts. This information is used to bind created hosts to the lockfile of this flake explicitly!
        #
        # ERROR; Requires 'rec' tagging the outermost attribute set to reference 'inputs' here
        # ERROR; Requires no other variable being introduced into this scope that shadows 'inputs'
        # SEEALSO; nixos {option}`nix.registry`
        # SEEALSO; ./nixosModules/nix-system.nix
        meta.inputs = inputs;
      };
    in
    let
      inherit (flake) inputs;

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
      lib = inputs.nixpkgs.lib.extend (inputs.nixpkgs.lib.composeManyExtensions [
        (_: _: { dns = inputs.dns.lib; }) # lib from dns.nix
        (_: _: self.outputs.lib) # Our own lib
      ]);

      # Shortcut to create behaviour that abstracts over different package indexes
      eachSystem = f: lib.genAttrs systems (system: f inputs.nixpkgs.legacyPackages.${system});

      # Same shortcut as eachSystem, but using a customized instantiation of nixpkgs.
      #
      # NOTE; Valid nixpkgs-config attributes can be found at pkgs/toplevel/default.nix
      # REF; https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/default.nix
      eachSystemOverride = nixpkgs-config: f: lib.genAttrs systems
        (system: f (import (inputs.nixpkgs) (nixpkgs-config // { localSystem = { inherit system; }; })));

      # Collect facts about all the host configurations defined in this flake
      #
      # WARN; This iteration over all nixosConfigurations slows down evaluation time by A LOT. The approach
      # must be removed/re-evaluated when eval times become embarassignly slow!
      #
      host-facts = (builtins.mapAttrs (_: v: v.config.proesmans.facts) self.outputs.nixosConfigurations)
        // (lib.pipe self.outputs.nixosConfigurations [
        # Keep hypervisor host configurations
        (lib.filterAttrs (_: v: lib.hasAttrByPath [ "microvm" "vms" ] v.config))
        (builtins.mapAttrs (_: v: v.config.microvm.vms))
        # Select and flatten all virtual machine configurations
        (lib.mapAttrsToList (host-name: guests:
          (lib.mapAttrsToList (guest-name: v: {
            "${guest-name}-${host-name}" = v.config.config.proesmans.facts;
          })) guests
        ))
        (lib.concatLists)
        (lib.mergeAttrsList)
      ]);

      # NixosModules that hold a fixed set of configuration that is re-usable accross different hosts.
      # eg; dns server program configuration, reused by all the dns server hosts (OSI layer 7 high-availability)
      # eg; virtual machine guest configuration, reused by all hosts that are running on top of a hypervisor
      #
      # SEEALSO; self.outputs.nixosModules
      profiles-nixos = lib.rakeLeaves ./source/nixosModules/profiles;
    in
    {
      # Builds an attribute set of all our library code.
      # Each library file is applied with the lib from nixpkgs.
      #
      # NOTE; This library set is extended into the nixpkgs library set later, see let .. in above.
      lib = { }
        // (import ./source/library/importers.nix (inputs.nixpkgs.lib))
        // (import ./source/library/network.nix (inputs.nixpkgs.lib));

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
              # See tasks.py for details on the operational workings of managing the nixos hosts.
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
                git bat
                outils# sha{1,256,5120}/md5
                nix-tree
                # For building and introspection
                nix-output-monitor
                nix-fast-build
                ;
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

      # Print and externally process host information with;
      # nix eval --json .#host-facts
      #
      # eg; To get a list of objects containing each host-name and domain-name, use the following jq expression
      # nix eval --json .#host-facts `
      # | jq 'to_entries | map({ "host-name": .value["host-name"], "domain-name": .value.management["domain-name"] })'
      #
      # Expose the collected facts about all the host configurations defined by this flake
      inherit host-facts;

      # nixOS modules are just lambda's with an attribute set as the first argument (arity of all nix functions is
      # always one). NixOS modules on their own do nothing, but need to be incorporated into a nixosConfiguration.
      #
      # Refer to nixosModules.hosts (or the filepath ./nixosModules/hosts) for the definition/configuration 
      # of each machine. Starting from the configuration.nix file, other nixos module files are imported.
      # The collective set of all imported modules is turned into a host configuration.
      # Because the configuration.nix file is typically imported first, it's called the toplevel (nixos) module.
      #
      # NOTE; The type of this value is attrSet[<name>, <path>]
      # eg {filesystem = ./nixosModules/filesystem.nix;}
      #
      # NOTE; Paths are a value type in nix, and nix will resolve these paths to their fixed store path
      # (eg /nix/store/aaabbbcccdddd/nixosModules/filesystem.nix) during/after evaluation (before derivations are created).
      # The prefix is the resulting path (/aaabbbcccddd) comes from the outPath attribute of this flake.
      nixosModules = (lib.rakeLeaves ./nixosModules);

      # nixosConfigurations hold the full interconnected configuration data to build a host, either pieces of it or
      # in its entirety.
      #
      # WARN; Deployment of hosts in this flake is handled by the "invoke" command, the nixos-anywhere info below is
      # kept to provide information on deeper internals.
      # SEEALSO; self.outputs.devShells.deployment-shell
      # SEEALSO; ./tasks.py file
      #
      #
      # Deploy with nixos-anywhere; nix run github:nix-community/nixos-anywhere -- --flake .#<machine-name (property of nixosConfigurations)> <user>@<ip address>
      # NOTE; nixos-anywhere will automatically look under #nixosConfigurations so that property component can be ommited from the command line
      # NOTE; <user> must be root or have passwordless sudo
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
      #
      #
      # Update with; nixos-rebuild switch --flake .#<machine-name> --target-host <user>@<ip address>
      # NOTE; nixos-rebuild will automatically look under #nixosConfigurations so that property component can be ommited from the command line
      # NOTE; <user> must be root or have passwordless sudo
      # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
      #
      #
      # NOTE; Optimizations like --use-substituters and caching can be used to speed up the building/install/update process. 
      # Using this optimization depends on the conditions of the build-host and target-host.
      # eg use it when the upload speed of the build-host is slower than the download speed of the target-host.
      #
      nixosConfigurations =
        let
          special-arguments = {
            # Define arguments here that must be be resolvable at module import stage, for all else use the _module.args option.
            # SEEALSO; meta-module, below
            special = {
              inputs = inputs;
              profiles = profiles-nixos;
            };
          };

          # Only the modules that are safe to include always (aka option definitions and gated configuration)
          nixos-modules = builtins.attrValues (
            lib.filterAttrs (name: _: name != "hosts" && name != "profiles" && name != "debug") self.outputs.nixosModules
          );

          meta-module = hostname: { config, ... }: {
            # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
            _file = ./flake.nix;

            # Preload nixos modules from this repository
            imports = nixos-modules
              ++ [
              # Options for vizualizing topology of configuration
              inputs.nix-topology.nixosModules.default
            ];

            config = {
              # Make the outputs of this flake available to the configurations
              #
              # WARN; Possible footgun with flake.outputs.host-facts; the facts of the current host configuration are also included.
              # This causes a hairpin access pattern, producing unexpected effects. (You'll understand when you experience it)
              _module.args.flake = flake;
              _module.args.meta-module = meta-module;

              # Nixos utils package is available as module argument, made available sorta like below.
              #_module.args.utils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" { inherit lib config pkgs; };

              # The hostname of each configuration _must_ match their attribute name.
              # This prevent the footgun of desynchronized identifiers.
              networking.hostName = lib.mkForce hostname;
            };
          };
        in
        {
          development = lib.nixosSystem {
            inherit lib;
            system = null; # Deprecated, use nixpkgs.hostPlatform option
            specialArgs = special-arguments;
            modules = [
              (meta-module "development")
              ./nixosModules/hosts/development/configuration.nix
            ];
          };

          buddy = lib.nixosSystem {
            inherit lib;
            system = null; # Deprecated, use nixpkgs.hostPlatform option
            specialArgs = special-arguments;
            modules = [
              (meta-module "buddy")
              ./nixosModules/hosts/buddy/configuration.nix
            ];
          };

          fart = lib.nixosSystem {
            inherit lib;
            system = null; # Deprecated, use nixpkgs.hostPlatform option
            specialArgs = special-arguments;
            modules = [
              (meta-module "fart")
              ./nixosModules/hosts/fart/configuration.nix
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
      # WARN; nix flake check will warn about this attribute existing because it's not defined within the
      # standard nix flake output schema. Harmless message.
      homeModules = (lib.rakeLeaves ./homeModules);

      # NOTE; Home modules above can be incorporated in a standalone configuration that evaluates independently
      # of nixos host configurations.
      # This is the same distinction that exists between nixosModules and nixosConfiguration, the latter is a 
      # compilation of all option values defined within nixosModules.
      #
      # I'm not doing homeConfigurations though, since the nixos integrated approach works well for me.
      # SEE ALSO; ./home/modules/home-manager.nix
      #
      # WARN; nix flake check will warn about this attribute existing because it's not defined within the
      # standard nix flake output schema. Harmless message.
      homeConfigurations = { };

      # Build a bootstrap image using;
      # nix build
      #
      # Build vsock-proxy, or any other program by attribute name using;
      # nix build .#vsock-proxy
      #
      # Collection of derivations that build into finished concrete file outputs, to be used as-is.
      # This flake is exactly producing tangible outputs but;
      #   - user module configuration, which must be wrapped into the home-manager platform
      #   - host module configuration, which must be wrapped into the nixos platform
      #   - host configuration, which must be installed through nixos-rebuild
      #   - configuration metadata, which must be post-processed
      #
      # This attribute set outputs two files to bootstrap a new development host somewhere (anywhere).
      # The default build output is an iso that can be injected into virtual machines or burned onto USB drives.
      # The default iso is basically a minimal image.
      # The development-iso attribute is basically the same as default plus a bigger payload size.
      packages = eachSystem (pkgs:
        # NOTE; lib.fix creates a recursive scope, sort of like let in {} with nix lazy evaluation.
        # ERROR; Don't use lib.{new,create}Scope because those inject additional attributes that 'nix flake check'
        # doesn't like!
        lib.fix (final:
          let
            # NOTE; Create our own callPackage function with our recursive scope, this function
            # will apply the necessary arguments to each package recipe.
            callPackage = pkgs.newScope (final // {
              # HERE; Add more custom package arguments. Only items that are _NOT_ derivations!

              inherit flake;
              nixosLib = lib;
            });
          in
          {
            # HERE; Add aliasses and/or overrides.

            # NOTE; You can find the generated iso file at ./result/iso/*.iso
            default = final.bootstrap;
            development = final.bootstrap.override { withDevelopmentConfig = true; };
          } //
          # NOTE; This function retrieves and imports "package.nix" files.
          lib.packagesFromDirectoryRecursive {
            inherit callPackage;
            directory = ./packages;
          })
      );

      # Execute and validate tests against this flake configuration;
      # nix-fast-build
      # [BROKEN] nix flake check --no-eval-cache --keep-going
      #
      # `nix flake check` by default evaluates and builds derivations (if applicable) of common flake schema outputs.
      # It's not necessary to explicitly add packages, devshells, nixosconfigurations (build.toplevel attribute) to this attribute set.
      # Add custom derivations, like nixos-tests or custom format outputs of nixosSystem, to this attribute set for
      # automated validation through a CLI-oneliner.
      #
      # ERROR; Do _not_ use `nix flake check` directly due to memory issues during evaluation. Use "nix-fast-build" or "hydra" instead!
      #
      # WARN; Not all CI systems actually build, but stop after evaluation! "nix-eval-jobs" for example only _evaluates_ but does not build!
      # This is important because nixos tests effectively run _during build_ (which doesn't really make sense but okay..)!
      checks = eachSystem (_pkgs: {
        # example = pkgs.testers.runNixOSTest {
        #   name = "example";
        #   nodes = { };
        #   testScript = ''
        #     # TODO
        #   '';
        # };
      });

      # Build everything defined (basically nix flake check);
      # [INTERACTIVE] nix-fast-build --flake .#hydraJobs
      # [CI] nix-fast-build --no-nom --skip-cached --flake ".#hydraJobs.$(nix eval --raw --impure --expr builtins.currentSystem)"
      #
      # NOTE; First attribute underneath hydraJobs is set to system to make filtering jobs easier.
      hydraJobs = eachSystem
        (pkgs: {
          recurseForDerivations = true;

          formatter = self.outputs.formatter.${pkgs.system};
          devShells = self.outputs.devShells.${pkgs.system};
          packages = self.outputs.packages.${pkgs.system};
          checks = self.outputs.checks.${pkgs.system};
          topology = self.outputs.topology.${pkgs.system}.config.output;
        }) // {
        no-system.recurseForDerivations = true;
        no-system.nixosConfigurations = lib.mapAttrs (_: v: v.config.system.build.toplevel) self.outputs.nixosConfigurations;
      };

      # Overwrite (aka patch) functionality defined by the inputs, mostly nixpkgs.
      #
      # These attributes are lambda's that don't do anything on their own. Use the `overlay`
      # options to incorporate them into your configuration.
      # eg; (nixos options) nixpkgs.overlays = self.outputs.overlays;
      # eg; (nix extensible attr set) _ = lib.extends (lib.composeManyExtensions (builtins.attrValues self.outputs.overlays));
      #
      # See also; nixosModules.nix-system
      overlays = { };

      # Render your topology via the command below, the resulting directory will contain your finished svgs.
      # nix build .#topology.x86_64-linux.config.output
      #
      # Constructs a visual topology of all the host configurations inside this flake. The code uses evalModules, which is the same
      # "platform" used by nixosSystem to process module files.
      topology = eachSystemOverride { overlays = [ inputs.nix-topology.overlays.default ]; } (
        pkgs: import inputs.nix-topology {
          inherit pkgs;
          modules = [
            # HELP; You own file to define global topology. Works in principle like a nixos module but uses different options.
            # HELP - ./topology.nix

            ({ config, ... }:
              let
                inherit (config.lib.topology) mkInternet mkRouter mkConnection;
              in
              {
                _file = ./flake.nix;
                config = {
                  # WARN; Provide all nixosConfigurations definitions
                  nixosConfigurations = self.nixosConfigurations;

                  nodes.internet = mkInternet {
                    connections = mkConnection "router" "ether1";
                  };

                  nodes.router = mkRouter "Mikrotik" {
                    info = "RB750Gr3";
                    image = ./assets/RB750Gr3-smol.png;
                    interfaceGroups = [ [ "ether2" "ether3" "ether4" "ether5" ] [ "ether1" ] ];
                    connections.ether2 = mkConnection "buddy" "30-lan";
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
              })
          ];
        }
      );
    };
}
