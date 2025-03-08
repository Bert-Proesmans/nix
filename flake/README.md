# Nix

(from the ground up)

## Bootstrap VM

1. Download latest bootstrap image from Github releases: [https://github.com/Bert-Proesmans/nix/releases/tag/latest](https://github.com/Bert-Proesmans/nix/releases/tag/latest)
2. Boot bare-metal or virtual machine from the ISO
3. Git clone this repository: [https://github.com/Bert-Proesmans/nix](https://github.com/Bert-Proesmans/nix)
4. Change directory into the cloned repository
5. Open development environment: `nix develop`
6. Install/deploy the development machine or any other: `invoke deploy development root@localhost` 

## Nix from scratch

1. Download bootstrap image from official distribution: [https://nixos.org/download/#nixos-iso](https://nixos.org/download/#nixos-iso)
2. Boot bare-metal or virtual machine from the ISO
3. Setup disks, partitions, and mounts
4. Generate a sample NixOS system configuration
    > nixos-generate-config --dir ./
5. Generate a sample flake configuration file
    > nix --extra-experimental-features "nix-command flakes" flake init
6. Do flake magix
    > I really have no easy explanation other than ["do what others do"](https://nixos.wiki/wiki/Flakes#Output_schema)
7. Build out your machine configuration and keep re-applying changes

## Nix IDE

VSCode can be used as an integrated development environment.
The development machine needs a package [nixos-vscode-server] installed that facilitates the VSCode server.
Within VSCode there is also an extension [Nix IDE] for syntax highlighting and formatting.

[nixos-vscode-server]: https://github.com/nix-community/nixos-vscode-server
[Nix IDE]: https://marketplace.visualstudio.com/items?itemName=jnoortheen.nix-ide

```nix
# SOURCE; https://github.com/nix-community/nixos-vscode-server/blob/1e1358493df6529d4c7bc4cc3066f76fd16d4ae6/README.md
{
  inputs.vscode-server.url = "github:nix-community/nixos-vscode-server";

  outputs = { self, nixpkgs, vscode-server }: {
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      modules = [
        vscode-server.nixosModules.default
        ({ config, pkgs, ... }: {
          services.vscode-server.enable = true;
        })
      ];
    };
  };
}
```

1. Add the services.vscode-server configuration to the development machine
1. Build the machine and connect from VSCode on your host over SSH to your development machine
