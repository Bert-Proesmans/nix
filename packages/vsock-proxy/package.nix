{ fetchCrate
, lib
, rustPlatform
}:
rustPlatform.buildRustPackage rec {
  pname = "vsock-proxy";
  version = "0.1.2";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-z27gFaK9OxvNUtDyVQ4pokRGSaaUlTlo50XKaRwUadk=";
  };

  cargoHash = "sha256-o4ifCJw8SbdsNThkW6nG3BgIHAdyLjoGG45sLtVL71o=";

  meta = {
    description = "A minimal CLI to proxy TCP traffic to or from VSock";
    longDescription = ''
      A utility crate for proxying connections between TCP and Vsock.
    '';
    homepage = "https://docs.rs/crate/vsock-proxy/${version}";
    license = with lib.licenses; [ mit ];
    maintainers = [ ];
    mainProgram = "vsock-proxy";
  };
}
