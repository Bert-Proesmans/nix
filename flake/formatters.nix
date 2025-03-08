{ inputs, pkgs }:
(inputs.treefmt-nix.lib.evalModule pkgs {
  projectRootFile = "flake.nix";

  programs.nixpkgs-fmt.enable = true;
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
}).config.build.wrapper
