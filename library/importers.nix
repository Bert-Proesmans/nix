# REF; https://github.com/divnix/digga/blob/baa54f8641ee9128cdda8b508553284c331fc9f1/src/importers.nix
nixpkgs-lib:
let
  flattenTree =
    /* *
       Synopsis: flattenTree _tree_

       Flattens a _tree_ of the shape that is produced by rakeLeaves.

       Output Format:
       An attrset with names in the spirit of the Reverse DNS Notation form
       that fully preserve information about grouping from nesting.

       Example input:
       ```
       {
       a = {
       b = {
       c = <path>;
       };
       };
       }
       ```

       Example output:
       ```
       {
       "a.b.c" = <path>;
       }
       ```
       *
    */
    tree:
    let
      op = sum: path: val:
        let
          pathStr =
            builtins.concatStringsSep "." path; # dot-based reverse DNS notation
        in
        if builtins.isPath val then
        # builtins.trace "${toString val} is a path"
          (sum // { "${pathStr}" = val; })
        else if builtins.isAttrs val then
        # builtins.trace "${builtins.toJSON val} is an attrset"
        # recurse into that attribute set
          (recurse sum path val)
        else
        # ignore that value
        # builtins.trace "${toString path} is something else"
          sum;

      recurse = sum: path: val:
        builtins.foldl' (sum: key: op sum (path ++ [ key ]) val.${key}) sum
          (builtins.attrNames val);
    in
    recurse { } [ ] tree;

  rakeLeaves =
    /* *
       Synopsis: rakeLeaves _path_

       Recursively collect the nix files of _path_ into attrs.

       Output Format:
       An attribute set where all `.nix` files and directories with `default.nix` in them
       are mapped to keys that are either the file with .nix stripped or the folder name.
       All other directories are recursed further into nested attribute sets with the same format.

       Example file structure:
       ```
       ./core/default.nix
       ./base.nix
       ./main/dev.nix
       ./main/os/default.nix
       ```

       Example output:
       ```
       {
       core = ./core;
       base = base.nix;
       main = {
       dev = ./main/dev.nix;
       os = ./main/os;
       };
       }
       ```
       *
    */
    dirPath:
    let
      seive = file: type:
        # Only rake `.nix` files or directories
        (type == "regular" && nixpkgs-lib.hasSuffix ".nix" file)
        || (type == "directory");

      collect = file: type: {
        name = nixpkgs-lib.removeSuffix ".nix" file;
        value =
          let path = dirPath + "/${file}";
          in if (type == "regular") || (type == "directory"
            && builtins.pathExists (path + "/default.nix")) then
            path
          # recurse on directories that don't contain a `default.nix`
          else
            rakeLeaves path;
      };

      files = nixpkgs-lib.filterAttrs seive (builtins.readDir dirPath);
    in
    nixpkgs-lib.filterAttrs (_n: v: v != { }) (nixpkgs-lib.mapAttrs' collect files);
in
{ inherit rakeLeaves flattenTree; }
