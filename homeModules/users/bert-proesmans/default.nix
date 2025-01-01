{ lib, pkgs, facts, osConfig, ... }:
{
  # Values are preset for the next attribute names;
  # - home.username
  # - home.homeDirectory
  imports = [ ];

  home.packages = [
    pkgs.dust
    pkgs.fd
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
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.ssh.enable = true;
  programs.ssh.hashKnownHosts = true;
  programs.ssh.forwardAgent = false;
  programs.ssh.matchBlocks =
    let
      resolve-endpoint = fact-node: lib.findFirst (x: x != null) fact-node [
        facts."${fact-node}".management.domain-name
        facts."${fact-node}".management.ip-address
      ];

      # Currently filtering out the current host itself to disambiguate connections, which often need to be handled seperately
      # unless a sort of network hairpin is provided.
      # TODO; A simple network hairpin could be a consistent DNS server reply.
      others-facts = lib.filterAttrs
        (_: v: osConfig.proesmans.facts.host-name != v.host-name && osConfig.proesmans.facts.host-name != v.meta.parent)
        facts;

      physical-hosts = lib.mapAttrs
        (name: _v: { hostname = resolve-endpoint name; })
        (lib.filterAttrs (_: v: !(builtins.elem "virtual-machine" v.tags)) others-facts);

      guest-proxy-command = facts:
        if facts.meta.vsock-vmm then "${lib.getExe pkgs.proesmans.firecracker-vsock-proxy} /run/microvm/vsock/${facts.host-name}.vsock 22"
        else "${lib.getExe pkgs.socat} - VSOCK-CONNECT:${toString facts.meta.vsock-id}:22";

      virtual-machines = lib.pipe others-facts [
        (lib.filterAttrs (_: v: builtins.elem "virtual-machine" v.tags))
        (lib.filterAttrs (_: v: v.meta.parent != null)) # Parent could be unset!
        (lib.mapAttrs
          (_name: v: {
            # ERROR; Using proxy/jumphost means your current host controls all network steering!
            # AKA your current host must instruct to switch over to VSOCK because there is no autonomy on
            # the jumphost, its ssh_config will not be used to connect to the next hop.
            # -ERROR- proxyJump = resolve-endpoint v.parent;
            proxyCommand = "ssh ${resolve-endpoint v.meta.parent} \"${guest-proxy-command v}\"";
          }))
      ];
    in
    physical-hosts // virtual-machines;

  programs.atuin.enable = true;
  programs.atuin.settings = {
    update_check = false;
    dialect = "uk";
    enter_accept = true;
    prefers_reduced_motion = true;
    filter_mode_shell_up_key_binding = "directory";
  };

  programs.bat.enable = true;
  programs.bat.config.theme = "Visual Studio Dark+";
  programs.broot.enable = true;
  programs.eza.enable = true;
  programs.eza.git = true;
  programs.fzf.enable = true;
  programs.ripgrep.enable = true;
  programs.ripgrep.arguments = [
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
  };

  # Ignore below
  home.stateVersion = "23.11";
}
