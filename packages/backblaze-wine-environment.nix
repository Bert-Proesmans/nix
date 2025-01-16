{ lib
, backblaze-installer
, runCommand
, wineWowPackages # 32+64 bit wine
, winetricks
}:
let
  wine = wineWowPackages.stable;

  installedEnvironment = runCommand "wine-env" { buildInputs = [ wine winetricks ]; } ''
    mkdir home
    export HOME="$(realpath home)"

    export WINEARCH="win64"
    export WINEDLLOVERRIDES="mscoree=" # Disable Mono installation

    wineboot --init

    # Run desktop in window
    winetricks vd="900x700"

    # Unpack MSI files instead of installing.
    # Besides unpacking the files this MSI database creates some shortcuts and auto-start entries.
    # We'll manually run the authentication program.
    msiexec /a "${backblaze-installer}" /q TARGETDIR="C:\Program Files (x86)\Backblaze"

    mkdir $out
    # Setup wine prefix with overlay filesystem, with read-only underlay at path `''${pkg}/share/.wine`.
    mv --verbose "''${HOME}/.wine" "$out/share"

    # Run sync gui with; "''${WINEPREFIX}/drive_c/Program Files (x86)/Backblaze/bzbui.exe" -noquiet
    # Run authentication gui with; "''${WINEPREFIX}/.wine/drive_c/Program Files (x86)/Backblaze/bzdoinstall.exe"
  '';
in
installedEnvironment
