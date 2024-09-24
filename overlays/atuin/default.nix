# This is an overlay lambda
_final: prev: {
  atuin = prev.atuin.overrideAttrs (old: {
    version = "${old.version}-zfs-fast";
    patches = [
      # Workaround sync hang with SQLite WAL
      # REF; https://github.com/atuinsh/atuin/issues/952
      #
      # Create patch;
      # 1. clone source
      # 2. make changes
      # 3. run git diff > 0001-make-atuin-on-zfs-fast-again.patch
      # 4. cry and fuck around because they changed the repo layout on master and the nix
      #    index has version 18.2.0 -> update paths in patch to match packaged version
      #     (the base path of git apply is the 'source' subdirectory)
      #
      # NOTE; Debug with nix build `--keep-failed`, this will tell you the temporary
      # build directory for inspection!
      ./0001-make-atuin-on-zfs-fast-again.patch
    ];

    # Disable tests to speed up packaging.
    # Assumes upstream has tested the package.
    doCheck = false;
  });
}
