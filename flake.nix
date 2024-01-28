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

  outputs = { self, nixpkgs, systems, treefmt-nix, ... }@inputs:
    let
      # Small tool to iterate over each target we can (cross-)compile for
      eachSystem = f:
        nixpkgs.lib.genAttrs (import systems)
        (system: f nixpkgs.legacyPackages.${system});

      # REF; https://github.com/Mic92/dotfiles/blob/0cf2fe94c553a5801cf47624e44b2b6d145c1aa3/devshell/flake-module.nix
      treefmt = eachSystem (pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          programs.nixfmt.enable = true;
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
        });
    in {
      formatter =
        eachSystem (pkgs: treefmt.${pkgs.system}.config.build.wrapper);

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          name = "b-NIX development";

          # REF; https://github.com/NixOS/nixpkgs/issues/58624#issuecomment-1576860784
          inputsFrom = [ ];

          nativeBuildInputs = [ treefmt.${pkgs.system}.config.build.wrapper ]
            ++ builtins.attrValues {
              # Python packages required for quick-commands wrapping complex operations
              inherit (pkgs.python3.pkgs) invoke deploykit;
            };

          # Software directly available inside the developer shell
          packages = builtins.attrValues { inherit (pkgs) nyancat git direnv; };
        };
      });

      nixosConfigurations = {
        # Build with; nix build .#nixosConfigurations.development.config.system.build.toplevel
        #
        # Deploy with nixos-anywhere; nix run github:nix-community/nixos-anywhere -- --flake .#development <user>@<ip address>
        # NOTE; nixos-anywhere will automatically look under #nixosConfigurations so that property component can be ommited from the command line
        # NOTE; <user> must be root or have passwordless sudo
        # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
        #
        # Update with; nixos-rebuild switch --flake .#development --target-host <user>@<ip address>
        # NOTE; nixos-rebuild will automatically look under #nixosConfigurations so that property component can be ommited from the command line
        # NOTE; <user> must be root or have passwordless sudo
        # NOTE; <ip address> of anything SSH-able, ssh config preferably has a configuration stanza for this machine
        #
        # NOTE; Optimizations like --use-substituters and caching can be used to speed up the building/install/update process. This depends on the conditions of the build-host and target-host
        development = nixpkgs.lib.nixosSystem {
          specialArgs = { }; # { inherit inputs; };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.vscode-server.nixosModules.default
            ({ lib, config, pkgs, ... }: {
              # Check if opt-in for nixos module(?)              
              _module.check = true;
              # Consistent defaults accross all machine configurations.
              system.stateVersion = lib.mkDefault "23.05";
              # The CPU target for this machine
              nixpkgs.hostPlatform = lib.mkDefault lib.systems.examples.gnu64;
              networking.hostName = lib.mkForce "development";
              networking.domain = lib.mkForce "alpha.proesmans.eu";

              # EFI boot!
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              # Make me a user!
              users.users.bertp = {
                isNormalUser = true;
                description = "Bert Proesmans";
                extraGroups = [ "wheel" ]
                  ++ lib.optional config.virtualisation.libvirtd.enable
                  "libvirtd" # NOTE; en-GB
                  ++ lib.optional config.networking.networkmanager.enable
                  "networkmanager";
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
                ];
              };

              # Allow for remote management
              services.openssh.enable = true;
              services.openssh.settings.PasswordAuthentication = false;

              # Allow privilege elevation to administrator role
              security.sudo.enable = true;
              # Allow for passwordless sudo
              security.sudo.wheelNeedsPassword = false;

              # Enable hooks for vscode-server, plus additional software for plugins
              services.vscode-server.enable = true;
              environment.systemPackages =
                builtins.attrValues { inherit (pkgs) nixpkgs-fmt rnix-lsp; };

              # Disk and partition layout
              disko.devices = {
                disk.disk1 = {
                  device = "/dev/sda";
                  type = "disk";
                  content = {
                    type = "gpt";
                    partitions = {
                      ESP = {
                        size = "500M";
                        type = "EF00";
                        content = {
                          type = "filesystem";
                          format = "vfat";
                          mountpoint = "/boot";
                        };
                      };
                      encryptedSwap = {
                        size = "3G";
                        content = {
                          type = "swap";
                          randomEncryption = true;
                        };
                      };
                      root = {
                        size = "100%";
                        content = {
                          type = "lvm_pv";
                          vg = "pool";
                        };
                      };
                    };
                  };
                };
                lvm_vg = {
                  pool = {
                    type = "lvm_vg";
                    lvs = {
                      root = {
                        size = "100%FREE";
                        content = {
                          type = "filesystem";
                          format = "ext4";
                          mountpoint = "/";
                          mountOptions = [ "defaults" ];
                        };
                      };
                    };
                  };
                };
              };
            })
          ];
        };
      };

      checks = eachSystem (pkgs:
        let
          currentSystemDerivations =
            (pkgs.lib.filterAttrs (_: nixos: nixos.pkgs.system == pkgs.system))
            self.outputs.nixosConfigurations;
          nixosHosts = pkgs.lib.mapAttrs' (name: nixos:
            pkgs.lib.nameValuePair "nixos-${name}"
            nixos.config.system.build.toplevel) currentSystemDerivations;
        in nixosHosts // self.outputs.devShells.${pkgs.system});
    };
}
