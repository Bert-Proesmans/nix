{ inputs, pkgs, ... }: {
    imports = [ inputs.vscode-server.nixosModules.default ];

    services.vscode-server.enable = true;

    environment.systemPackages =
        builtins.attrValues { inherit (pkgs) nixpkgs-fmt rnix-lsp; };
}
