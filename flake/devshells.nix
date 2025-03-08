{ lib, pkgs, }: {
  default = pkgs.mkShellNoCC {
    name = "b-NIX development";

    nativeBuildInputs = [
      # Python packages to easily execute maintenance and build tasks for this flake.
      # See tasks.py for details on the operational workings of managing the nixos hosts.
      pkgs.python3.pkgs.invoke
      pkgs.python3.pkgs.deploykit
    ];

    # Software directly available inside the developer shell
    packages = [
      # For fun
      pkgs.nyancat
      pkgs.figlet
      # For development
      pkgs.git
      pkgs.bat
      pkgs.outils # sha{1,256,5120}/md5
      pkgs.nix-tree
      # For building and introspection
      pkgs.nix-output-monitor
      pkgs.nix-fast-build
      # For secret material
      pkgs.sops
      pkgs.ssh-to-age
      pkgs.rage
      # For deploying new hosts
      pkgs.nixos-anywhere
    ];

    # Open files within the visual code window
    EDITOR =
      let
        script = pkgs.writeShellApplication {
          name = "find-editor";
          runtimeInputs = [ pkgs.nano ];
          text = ''
            if type "code" > /dev/null; then
              # Since VScode works interactively there is an instant process fork.
              # The code calling $EDITOR is (very likely) synchronous, so we want to wait until
              # the specific (new) editor pane has closed!
              exec code --wait "$@"
            fi

            exec nano "$@"
          '';
        };
      in
      lib.getExe script;
  };
}
