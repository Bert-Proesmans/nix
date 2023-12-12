{self, lib', inputs}:
let
    inherit (self) outputs;

    prelude = {lib, ...}: {
        _module.check = true;
        # Consistent defaults accross all machine configurations.
        system.stateVersion = lib.mkDefault "23.05";
    };

    # nixos module configuration that makes the current flake available at /run/booted-system/flake
    flake-symlink = _: {
        imports = [ inputs.srvos.nixosModules.common ];
        srvos.flake = self;
    };

    nix-configuration = {config, lib, inputs, ...} : {
        imports = [ inputs.srvos.nixosModules.common ];
        # Lock inputs on the target machine, so all dev machines and deployed configurations share the
        # exact same version of repositories.
        nix.registry = lib.mapAttrs
            # nix.registry.<name>.flake must be set for each input
            (_name: flake: {inherit flake;})
            # Whitelisted flakes to bring over to the target
            # Add additional package repositories here (if the required software is out-of-tree@nixpkgs)
            # nixpkgs is a symlink to the stable source, kept for consistency with guides
            {inherit (inputs) nixpkgs nixos-stable nixos-unstable;};

        # Make legacy nix commands consistent with flake sources!
        nix.nixPath = ["/etc/nix/path"];
        environment.etc = lib.mapAttrs'
            (name: value: {
                name = "nix/path/${name}";
                value.source = value.flake;
            })
            config.nix.registry;
    };

    bertp = {config, lib, ...}: {
        users.users.bertp = {
            isNormalUser = true;
            description = "Bert Proesmans";
            extraGroups = [ "wheel" ]
            ++ lib.optional config.virtualisation.libvirtd.enable "libvirtd" # NOTE; en-GB
            ++ lib.optional config.networking.networkmanager.enable "networkmanager";
            openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUcKAUBNwlSZYiFc3xmCSSmdb6613MRQN+xq+CjZR7H bert@B-PC"
            ];
        };
    };
in
{
    development = (lib'.makeOverridable lib'.nixosSystem) {
      specialArgs = {inherit inputs outputs;};
      modules = [
        outputs.nixosModules.strip-on-virtualisation
        outputs.nixosModules.be-internationalisation
        outputs.nixosModules.vscode-server
        prelude
        flake-symlink
        nix-configuration
        bertp
        ({ lib, ... }: {
            imports = [ inputs.srvos.nixosModules.server ];

            nixpkgs.hostPlatform = lib.mkDefault lib.systems.examples.gnu64;
            networking.hostName = lib.mkForce "development";
            networking.domain = lib.mkForce "alpha.proesmans.eu";

            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;
        })
        ({
            imports = [ inputs.disko.nixosModules.disko ];
            disko.devices = {
                disk.sda = {
                    type = "disk";
                    device = "/dev/sda";
                    content = {
                        type = "table";
                        format = "gpt";
                        partitions = [
                        {
                            name = "ESP";
                            start = "1MiB";
                            end = "512MiB";
                            bootable = true;
                            content = {
                                type = "filesystem";
                                format = "vfat";
                                mountpoint = "/boot";
                            };
                        }
                        {
                            name = "root";
                            start = "512MiB";
                            end = "-3G";
                            bootable = true;
                            part-type = "primary";
                            content = {
                                type = "filesystem";
                                format = "ext4";
                                mountpoint = "/";
                            };
                        }
                        {
                            name = "swap";
                            start = "-3G";
                            end = "100%";
                            part-type = "primary";
                            content = {
                                type = "swap";
                                randomEncryption = true;
                            };
                        }
                        ];
                    };
                };
            };
        })
        ({ config, options, lib, pkgs, ... }:
        {
            networking.usePredictableInterfaceNames = true;
            systemd.network.networks = {
                "10-wan" = {
                    matchConfig.Name = [ "enp1s0" ];

                    # Setting up IPv6.
                    # REF; https://unique-local-ipv6.com/
                    # ULA range; fd01:1336:f997::/48
                    # Subnet 0000
                    address = [ "fd01:1336:f997::10/64" ];
                    gateway = [ "fe80::1" ];

                    networkConfig = {
                        # IPv6 has to be manually configured.
                        DHCP = "ipv4";

                        LinkLocalAddressing = "ipv6";
                        IPForward = true;
                    };
                };
            };
        })
        ({lib, ...}: {
            virtualisation.hypervGuest.enable = true;

            # Testing
            users.mutableUsers = lib.mkForce true;

            # NOTE; Empty first line is intentional
            services.getty.helpLine = lib.mkAfter ''

                \4    \6
                ---
                eth0; \4{eth0}    \6{eth0}
                eth1; \4{eth1}    \6{eth1}
                eth2; \4{eth2}    \6{eth2}
            '';
        })
      ];
    };
}
