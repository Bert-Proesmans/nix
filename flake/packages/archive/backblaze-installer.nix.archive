{ fetchurl
, runCommand
, wineWowPackages # 32+64 bit wine
, findutils
}:
let
  wine = wineWowPackages.stable;

  installPackage = fetchurl {
    url = "https://www.backblaze.com/win32/install_backblaze.exe";
    # nix-prefetch-url <URL>
    # Defaults to outputting sha256 hash.
    # Note that the installer is not version pinned! Only when the hash is manually changed a redownload will occur
    # (or a nix garbage collect has run)
    sha256 = "1vf1x9ss8wdbjbj169819vikrrj1j703nbf83zl6xm4s5sml620n";
  };

  msiPackage = runCommand "extract-msi" { buildInputs = [ wine findutils ]; } ''
    mkdir home
    export HOME="$(realpath home)"

    # Wine exits with error because binary tries to display a window, ignore
    wine "${installPackage}" -unpackonly || true
    candidates=($(find "$HOME"/.wine/drive_c/users/nixbld/Temp -name "bzinstall*.msi" -print))
    if [[ ''${#candidates[@]} -ne 1 ]]; then
      echo "Multiple MSI files found! Exiting.." 1>&2
      exit 1
    fi

    cp "''${candidates[0]}" "$out"
  '';
in
msiPackage
