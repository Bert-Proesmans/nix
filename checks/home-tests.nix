{ ... }: {
  # DON'T, just DON'T.
  # I've tried to build an integration test for 3 days and can't get it to work, expecting normal nix-behaviour as pre-condition.
  # There is something weird going on with nix-env and the testing sandbox that breaks home-manager's "activate" (and
  # probably "nixos-rebuild" too since they use the same underlying code)
  # Standalone home-manager configuration is not exported, since it's unused and untested.
  # The home-manager configuration integrated into nixos configuration can not be integration tested in an interesting way.
}
