{ flake, config, ... }: {
  # In this file you'll find changes that are communicated upstream but not yet incorporated
  # into the standard set of dependencies.
  # Expect this file to dissapear in time.

  imports = [
    # Look at updates to file nixos/modules/module-list.nix
    "${flake.inputs.immich-review}/nixos/modules/services/web-apps/immich.nix"
  ];

  # This overlay should not be applied to the other nixpkgs variant. AKA not using option proesmans.nix.overlays for this.
  nixpkgs.overlays =
    let
      # WARN; In case of overlay misuse prevent the footgun of infinite nixpkgs evaluations. That's why the import
      # is pulled outside the overlay body.
      immich-pkgs = (import flake.inputs.immich-review) {
        inherit (config.nixpkgs) config;
        localSystem = config.nixpkgs.hostPlatform;
      };
    in
    [
      (final: _prev: {
        immich-review = immich-pkgs;
        immich = final.immich-review.immich;
      })
    ];

  services.immich = {
    redis.host = "/run/redis-immich/redis.sock";
  };

  systemd.services.immich-server = {
    after = [ "redis-immich.service" "postgresql.service" ];
  };

  systemd.services.immich-machine-learning = {
    after = [ "redis-immich.service" "postgresql.service" ];
  };
}
