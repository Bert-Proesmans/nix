final: previous: {
  # NOTE; Must use the elaborate overlay to get to "cargoHash".
  # CargoHash is an input to buildRustPackage which cannot be overriden with "overrideAttrs" because that
  # function only overrides arguments into "mkDerivation".
  # INFO; cargoHash is an abstraction on top of cargoDeps, which is an input derivation (like src).
  vaultwarden = final.callPackage previous.vaultwarden.override {
    rustPlatform = final.rustPlatform // {
      buildRustPackage =
        old:
        final.rustPlatform.buildRustPackage (
          old
          // {
            version = "1.35-PREVIEW-2025-12-17";

            src = final.fetchFromGitHub {
              owner = "dani-garcia";
              repo = "vaultwarden";
              rev = "57bdab15504ff874f0ad6cb93f03292a70e4b365";
              hash = "sha256-7DBSRaV4AvMFQgRBdnCbP+OX2+aZVomQHm+MbEHVKIE=";
            };
            cargoHash = "sha256-laCbtPeOjMg68SDdNAYWdFrxfIcQYYjo6BEM6lnBvn8=";

            patches = (old.patches or [ ]) ++ [
              # Patch against commit 57bdab15504ff874f0ad6cb93f03292a70e4b365
              ./allow-custom-rp_id.patch
            ];
          }
        );
    };
  };
}
