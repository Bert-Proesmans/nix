rec {
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

  outputs = { self, ... }@args:
    let
      # The original input metadata can be reused when building the nix registry configuration of
      # the hosts. Using this information bounds the hosts to the lockfile of this flake explicitly!
      #
      # SEEALSO; nixos option nix.registry
      # SEEALSO; ./nixosModules/nix-system.nix
      flake-meta.inputs = inputs;
    in
    let
      # Rebinding of args to the name 'inputs'.
      #
      # ERROR; Needs a double let .. in binding as to not clobber the variable `inputs`.
      # `inputs` is canonically the variable used to reference all _resolved_ inputs, but
      # we're also interested in the unresolved inputs!
      inputs = args;

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

      # NixosModules that hold a fixed set of configuration that is re-usable accross different hosts.
      # eg; dns server program configuration, reused by all the dns server hosts (OSI layer 7 high-availability)
      # eg; virtual machine guest configuration, reused by all hosts that are running on top of a hypervisor
      #
      # SEEALSO; self.outputs.nixosModules
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
      nixosModules = lib.filterAttrs (name: _: name != "hosts" && name != "profiles" && name != "debug") (lib.rakeLeaves ./nixosModules);

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
          # Read details from each host to share them with all other hosts.
          #
          # NOTE; The facts are collected through the use of a nixos module that shapes the data into "freeform schema".
          # Freeform schema here means there is a limited schema pre-defined, and individual configurations can add 
          # more schema nodes to their facts collection as required.
          configuration-facts = builtins.mapAttrs (_: v: v.config.proesmans.facts) self.outputs.nixosConfigurations;
          # Prevent the footgun of infinite recursion by preventing hosts from accessing their own facts table.
          # facts-no-circular = hostname: lib.filterAttrs (name: _: name != hostname) configuration-facts;

          meta-module = hostname: { config, ... }: {
            # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
            _file = ./flake.nix;

            # Make all custom nixos options available to the host configurations.
            imports = builtins.attrValues self.outputs.nixosModules;

            config = {
              # Flake inputs are used for importing additional nixos modules.
              # ERROR; Attributes that must be resolved during import evaluation _must_ be passed into the nixos
              # configuration through specialArgs!
              # _module.args.flake.inputs = args;

              _module.args.flake-overlays = self.outputs.overlays;
              _module.args.home-configurations = self.outputs.homeModules.users;
              # TODO
              _module.args.facts = { }; #configuration-facts;

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
            specialArgs = {
              # Set here arguments that must be be resolvable at module import stage,
              # for all else use _module.args option.
              # See also; meta-module, above
              flake.inputs = inputs;
              flake.meta.inputs = flake-meta.inputs;
              profiles = profiles-nixos;
            };
            modules = [
              (meta-module "development")
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
              flake.inputs = inputs;
              flake.meta.inputs = flake-meta.inputs;
              profiles = profiles-nixos;
            };
            modules = [
              (meta-module "buddy")
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

      # TODO
      packages = eachSystem (pkgs:
        let
          forced-system = pkgs.system;

          # NOTE; Minimal installer based host to get new hosts up and running
          bootstrap = lib.nixosSystem {
            system = null;
            lib = lib;
            specialArgs = {
              flake.inputs = inputs;
              flake.meta.inputs = flake-meta.inputs;
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

                  users.users.bert-proesmans = {
                    isNormalUser = true;
                    description = "Bert Proesmans";
                    extraGroups = [ "wheel" ];
                    openssh.authorizedKeys.keys = [
                      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
                    ];
                  };

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

          # Using the handy extendModules function to append more contents to the basic bootstrap image.
          # The entire point of this ISO is to work the size <-> RAM usage balance, see option isoImage.storeContents.
          development-iso = (bootstrap.extendModules {
            modules = [
              ({ profiles, ... }: {
                # This is an anonymous module and requires a marker for error messages and nixOS module accounting.
                _file = ./flake.nix;
                key = "${./flake.nix}?development-iso";

                imports = [
                  profiles.development-bootstrap
                  # NOTE; Explicitly not importing the nixosModules to keep configuration minimal!
                ];

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
      checks = eachSystem (pkgs: { });

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
