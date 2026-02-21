_final: previous: {
  vaultwarden = previous.vaultwarden.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # Patch against v1.35.3
      ./allow-custom-rp_id.patch
    ];
  });
}
