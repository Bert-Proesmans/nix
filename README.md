# Nix

(from the ground up)

## Bootstrap VM

1. Download the nixos minimal installer ISO
1. Create a VM to boot this installer ISO

> Bonus points for setting up SSH
> 1. Set a password on the nixos-install machine
> 1. Setup host ssh config to connect to machine

3. Generate a sample NixOS system configuration
    > nixos-generate-config --dir ./
1. Generate a sample flake configuration file
    > nix --extra-experimental-features "nix-command flakes" flake init
1. Do flake magix
    > I really have no easy explanation other than ["do what others do"](https://nixos.wiki/wiki/Flakes#Output_schema)
1. Build an installer image to install your development machine on top of the VM currently booting that installer image

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
