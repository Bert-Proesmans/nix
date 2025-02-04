{ lib
, writeShellApplication
, backblaze-install-patched
, wineWowPackages # 32+64 bit wine
, winetricks
, virtualgl
, libraries ? [ ] # Libraries to add to LD_LIBRARY_PATH
}:
let
  wine = wineWowPackages.stable;
  wineFonts = "${wineWowPackages.fonts}/share/fonts/wine";
in
writeShellApplication {
  name = "run-backblaze-wine-environment";
  runtimeInputs = [ wine winetricks virtualgl ];
  text = ''
    DRIVER_LIB_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib"
    LD_LIBRARY_PATH="${lib.makeLibraryPath libraries}:''${LD_LIBRARY_PATH:-''$DRIVER_LIB_PATH}"
    export LD_LIBRARY_PATH

    WINEARCH="win64"; export WINEARCH
    # mscoree dll linking to null disables the request for Mono installation on init.
    # we don't need mono as we're going to install netframework when the environment initializes.
    WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:-mscoree=}"; export WINEDLLOVERRIDES

    if [ -z "$WINEPREFIX" ]; then
      echo 'WINE: No Wine prefix environment variable set! Make sure to execute _export WINEPREFIX="<your directory>"_ first.'
      exit 1
    fi

    if [ ! -d "$WINEPREFIX" ]; then
      echo 'WINE: No wine environment found at WINEPREFIX, starting initialize'

      wineboot --init
      wineserver --wait
      
      winecfg -v win11
      wineserver --wait
      
      winetricks --unattended dotnet48
      wineserver --wait

      pushd "$WINEPREFIX"/drive_c/windows/Fonts
      find ${wineFonts} -type f -name '*.ttf' -exec ln --symbolic "{}" . \;
      popd
      
      cp '${backblaze-install-patched}' "$WINEPREFIX"/drive_c/backblaze_installer.msi
      wine msiexec /quiet /i 'C:\backblaze_installer.msi' 'TARGETDIR="C:\Program Files (x86)\Backblaze"'
      wineserver --wait

      echo "Wine initialisation done" >&2
    fi

    [ -f "$WINEPREFIX"/drive_c/backblaze_installer.msi ] && rm "$WINEPREFIX"/drive_c/backblaze_installer.msi

    if [ "$DISABLE_VIRTUAL_DESKTOP" = "true" ]; then
      echo "WINE: DISABLE_VIRTUAL_DESKTOP=true - Virtual Desktop mode will be disabled"
      winetricks vd=off
    else
      echo "WINE: DISABLE_VIRTUAL_DESKTOP=false - Showing wine desktop in window"
      winetricks vd="900x700"
    fi

    while [ ! -f "$WINEPREFIX"/drive_c/ProgramData/Backblaze/bzdata/bzvol_system_volume/bzvol_id.xml ]
    do
      vglrun wine 'C:\Program Files (x86)\Backblaze\bzdoinstall.exe' -doinstall 'C:\Program Files (x86)\Backblaze'
      wineserver --wait
    done

    vglrun wine 'C:\Program Files (x86)\Backblaze\bzbui.exe' -noquiet
    wineserver --wait
  '';
}
