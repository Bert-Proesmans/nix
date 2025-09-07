{
  lib,
  pkgs,
  nixosConfig,
  ...
}:
{
  # Values are preset for the next attribute names;
  # - home.username
  # - home.homeDirectory
  imports = [ ];

  home.packages = [
    pkgs.dust
    pkgs.mdcat
  ];

  home.keyboard.options = [
    # CAPS-LOCK -> CONTROL
    "ctrl:nocaps"
    # SHIFT-L + SHIFT-R -> CAPS LOCK
    "shift:both_capslock"
  ];

  programs.bash.enable = true;
  programs.bash.shellOptions = [
    # Append to history file rather than replacing it.
    "histappend"

    # check the window size after each command and, if
    # necessary, update the values of LINES and COLUMNS.
    "checkwinsize"

    # Extended globbing.
    "extglob"
    "globstar"

    # Warn if closing shell with running jobs.
    "checkjobs"

    # Ignore minor small edit distances on misspellings of cd argument
    "cdspell"
  ];
  programs.bash.shellAliases = {
    ".." = "cd ..";
    # ls -like requests are handled by EZA
    # ll = "ls -lah";

    cat = "bat --paging=never";

    gc = "git commit";
    ga = "git commit --amend";
  };

  # Make the home-manager CLI/tools available to the user
  # programs.home-manager.enable = true;

  # Automatically activate developer environment when entering project folders.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config = {
      load_dotenv = true;
      strict_env = true;
      warn_timeout = "5s";
      global.hide_env_diff = true;
    };
  };

  programs.ssh.enable = true;
  programs.ssh.hashKnownHosts = true;
  programs.ssh.forwardAgent = false;
  programs.ssh.matchBlocks =
    let
      inherit (nixosConfig.networking) hostName;
      other-facts = lib.filterAttrs (k: _v: k != "self" && k != hostName) nixosConfig.proesmans.facts;
    in
    lib.mapAttrs (k: v: { hostname = v.ipAddress or "${k}.${v.domainName}"; }) other-facts;

  programs.atuin.enable = true;
  programs.atuin.settings = {
    update_check = false;
    dialect = "uk";
    enter_accept = true;
    prefers_reduced_motion = true;
    filter_mode_shell_up_key_binding = "directory";
  };

  programs.bat.enable = true;
  programs.bat.extraPackages = [ pkgs.bat-extras.batman ];
  programs.bat.config.theme = "Visual Studio Dark+";
  programs.broot.enable = true;
  programs.eza.enable = true;
  programs.eza.git = true;
  programs.fzf.enable = true;
  programs.fd.enable = true;
  programs.fd.ignores = [
    ".git/"
    "*.bak"
  ];
  programs.fd.extraOptions = [
    "--hidden"
    "--ignore-case"
    "--absolute-path"
  ];
  programs.ripgrep.enable = true;
  programs.ripgrep.package = pkgs.ripgrep-all;
  programs.ripgrep.arguments = [
    "--hidden"
    # NOTE; rg follows users gitignore
    "--max-columns=150" # Hard limit on line length
    "--max-columns-preview"
    "--smart-case" # Don't care about case
  ];
  programs.tealdeer.enable = true;
  # Enables command 'tldr'
  programs.tealdeer.settings = {
    updates.auto_update = true;
    display.use_pager = true;
  };

  programs.git = {
    enable = true;
    userName = "Bert Proesmans";
    userEmail = "bproesmans@hotmail.com";

    delta.enable = true;
    delta.options = {
      interactive.keep-plus-minus-markers = false;
    };

    extraConfig = {
      log.date = "iso";
      init.defaultBranch = "master";
      commit.verbose = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      help.autocorrect = 10;
      branch.sort = "-committerdate";
      tag.sort = "taggerdate";
      #
      diff.algorithm = "histogram";
      # Give detected moves a different color
      diff.colorMoved = "default";
      diff.colorMovedWS = "allow-indentation-change";
      #
      # ZDiff3 displays code from the earlier commit in the middle.
      # This approach makes it easier to decide what the merge of both conflicting code
      # changes has to become.
      # eg
      # <<<<<<< HEAD
      # def parse(input):
      #     return input.split("\n")
      # ||||||| b9447fc
      # def parse(input):
      #     return input.split("\n\n")
      # =======
      # def parse(text):
      #     return text.split("\n\n")
      # >>>>>>> somebranch
      merge.conflictstyle = "zdiff3";
      # Automatically squash all fixup commits on rebase.
      # Used with `git commit --fixup COMMIT_ID`, alternative to `git commit --amend` for
      # latest commit.
      rebase.autosquash = "true";
      rebase.autostash = true;
      rebase.updateRefs = true;
      # Remember merge conflict resolution during rebase and automatically re-apply when
      # similar conflicts are detected. GODS GIFT BRUH
      rerere.enabled = true;
      #
      commit.gpgSign = false;
      tag.gpgSign = false;
      gpg.format = "ssh";
      # user.signingKey = null;
      #
      transfer.fsckobjects = true;
      fetch.fsckobjects = true;
      receive.fsckObjects = true;
    };

    ignores = [
      # Ignore all dotfiles and dot directories except gitignore/gitkeep
      ".*"
      "!.gitignore"
      "!.gitkeep"
      #
      "*.pdb"
      "*.qcow2"
      # Normally any non-leading slash forces the match to start at the root of the repo.
      # But result could be a directory _or file_ symlink, and is a pretty generic name too, so it's pinned
      # to the root explicitly.
      "/result"
      # These match directories with same name, at any level
      "debug/"
      "target/"
    ];
  };

  editorconfig.enable = true;
  editorconfig.settings = {
    "*" = {
      charset = "utf-8";
      end_of_line = "lf";
      trim_trailing_whitespace = true;
      insert_final_newline = true;
      max_line_width = 130;
      indent_style = "tab";
      indent_size = 2;
    };
    "*.nix" = {
      indent_size = 4;
    };
  };

  # Ignore below
  home.stateVersion = "23.11";
}
