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
      #
      # TreeFMT is built to be used with "flake-parts", but we're building the flake from scratch on this one! 
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
      # Format entire flake with;
      # nix fmt
      formatter =
        eachSystem (pkgs: treefmt.${pkgs.system}.config.build.wrapper);

      # Build development shell with;
      # nix flake develop
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          name = "b-NIX development";

          # REF; https://github.com/NixOS/nixpkgs/issues/58624#issuecomment-1576860784
          inputsFrom = [ ];

          nativeBuildInputs = [ treefmt.${pkgs.system}.config.build.wrapper ]
            ++ builtins.attrValues {
              # Python packages to easily execute maintenance and build tasks for this flake.
              # See tasks.py TODO
              inherit (pkgs.python3.pkgs) invoke deploykit;
            };

          # Software directly available inside the developer shell
          packages = builtins.attrValues { inherit (pkgs) nyancat git; };
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
          specialArgs = { inherit inputs; };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.vscode-server.nixosModules.default
            ({ lib, config, pkgs, inputs, ... }: {
              # Check if opt-in for nixos module(?)              
              _module.check = true;
              # Consistent defaults accross all machine configurations.
              system.stateVersion = lib.mkDefault "23.05";
              # The CPU target for this machine
              nixpkgs.hostPlatform = lib.mkDefault lib.systems.examples.gnu64;
              networking.hostName = lib.mkForce "development";
              networking.domain = lib.mkForce "alpha.proesmans.eu";

              # Load Hyper-V kernel modules
              virtualisation.hypervGuest.enable = true;

              # EFI boot!
              boot.loader.systemd-boot.enable = true;
              # Filesystem access to the EFI variables is only applicable when installing a system!
              #boot.loader.efi.canTouchEfiVariables = true;

              boot.tmp.cleanOnBoot = true;

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

              # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/nix.nix
              # Nix configuration

              # Fallback quickly if substituters are not available.
              nix.settings.connect-timeout = 5;

              # Enable flakes
              nix.settings.experimental-features =
                [ "nix-command" "flakes" "repl-flake" ];

              # The default at 10 is rarely enough.
              nix.settings.log-lines = lib.mkDefault 25;

              # Avoid disk full issues
              nix.settings.max-free = lib.mkDefault (3000 * 1024 * 1024);
              nix.settings.min-free = lib.mkDefault (512 * 1024 * 1024);

              # TODO: cargo culted.
              nix.daemonCPUSchedPolicy = lib.mkDefault "batch";
              nix.daemonIOSchedClass = lib.mkDefault "idle";
              nix.daemonIOSchedPriority = lib.mkDefault 7;

              # Make builds to be more likely killed than important services.
              # 100 is the default for user slices and 500 is systemd-coredumpd@
              # We rather want a build to be killed than our precious user sessions as builds can be easily restarted.
              systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust =
                lib.mkDefault 250;

              # Avoid copying unnecessary stuff over SSH
              nix.settings.builders-use-substitutes = true;

              # Assist nix-direnv, since project devshells aren't rooted in the computer profile, nor stored in /nix/store
              nix.settings.keep-outputs = true;
              nix.settings.keep-derivations = true;

              # Make legacy nix commands consistent with flake sources!
              # Register versioned flake inputs into the nix registry for flake subcommands
              # Register versioned flake inputs as channels for nix (v2) commands

              # Each input is mapped to 'nix.registry.<name>.flake = <flake store-content>'
              nix.registry = lib.mapAttrs (_name: flake: { inherit flake; })
              # Add additional package repositories here (if the required software is out-of-tree@nixpkgs)
              # nixpkgs is a symlink to the stable source, kept for consistency with online guides
                { inherit (inputs) nixpkgs nixos-stable nixos-unstable; };

              nix.nixPath = [ "/etc/nix/path" ];
              environment.etc = lib.mapAttrs' (name: value: {
                name = "nix/path/${name}";
                value.source = value.flake;
              }) config.nix.registry;

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

              # Automatically load development shell in project working directories
              programs.direnv.enable = true;
              programs.direnv.nix-direnv.enable = true;

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

              # REF; https://github.com/nix-community/srvos/blob/bf8e511b1757bc66f4247f1ec245dd4953aa818c/nixos/common/networking.nix

              # Networking configuration
              # Allow PMTU / DHCP
              networking.firewall.allowPing = true;

              # Keep dmesg/journalctl -k output readable by NOT logging
              # each refused connection on the open internet.
              networking.firewall.logRefusedConnections = false;

              # Use networkd instead of the pile of shell scripts
              networking.useNetworkd = true;
              networking.useDHCP = false;

              # The notion of "online" is a broken concept
              # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
              systemd.services.NetworkManager-wait-online.enable = false;
              systemd.network.wait-online.enable = false;

              # FIXME: Maybe upstream?
              # Do not take down the network for too long when upgrading,
              # This also prevents failures of services that are restarted instead of stopped.
              # It will use `systemctl restart` rather than stopping it with `systemctl stop`
              # followed by a delayed `systemctl start`.
              systemd.services.systemd-networkd.stopIfChanged = false;
              # Services that are only restarted might be not able to resolve when resolved is stopped before
              systemd.services.systemd-resolved.stopIfChanged = false;

              # Hyper-V does not emulate PCI devices, so network adapters remain on their ethX names
              # eth0 receives an address by DHCP and provides the default gateway route
              # eth1 is configured with a stable address for SSH
              networking.interfaces.eth0.useDHCP = true;
              networking.interfaces.eth1.ipv4.addresses = [{
                # V4 link local address
                address = "169.254.245.139";
                prefixLength = 24;
              }];

              # Avoid TOFU MITM with github by providing their public key here.
              programs.ssh.knownHosts = {
                "github.com".hostNames = [ "github.com" ];
                "github.com".publicKey =
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

                "gitlab.com".hostNames = [ "gitlab.com" ];
                "gitlab.com".publicKey =
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

                "git.sr.ht".hostNames = [ "git.sr.ht" ];
                "git.sr.ht".publicKey =
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
              };

              # Enroll some more trusted binary caches
              nix.settings.trusted-substituters = [
                "https://nix-community.cachix.org"
                "https://cache.garnix.io"
                "https://numtide.cachix.org"
              ];
              nix.settings.trusted-public-keys = [
                "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
                "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
              ];
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
