{ lib
, writeShellApplication
, backblaze-install-patched
, wineWowPackages # 32+64 bit wine
, winetricks
}:
let
  wine = wineWowPackages.stableFull;
in
writeShellApplication {
  name = "run-backblaze-wine-environment";
  runtimeInputs = [ wine winetricks ];
  text = ''
    export WINEARCH="win64"
    export WINEDLLOVERRIDES=""

    if [ -z "$WINEPREFIX" ]; then
      echo 'No Wine prefix environment variable set! Make sure to execute _export WINEPREFIX="<your directory>"_ first.'
      exit 1
    fi

    if [ ! -d "$WINEPREFIX" ]; then
      wineboot --init
      wineserver --wait
      
      winecfg -v win11
      wineserver --wait

      # Run desktop in window
      winetricks vd="900x700"
      winetricks --unattended dotnet48
      wineserver --wait
      
      cp '${backblaze-install-patched}' "$WINEPREFIX"/drive_c/backblaze_installer.msi
      wine msiexec /quiet /i 'C:\backblaze_installer.msi' TARGETDIR="C:\Program Files (x86)\Backblaze"
    fi

    # Run authentication gui with; wine "C:/Program Files (x86)/Backblaze/bzdoinstall.exe"
    # Run sync gui with; wine "C:/drive_c/Program Files (x86)/Backblaze/bzbui.exe" -noquiet
    
    # TODO; Perform check for logged in token and auto-start bzbui
    # Then wait for wine exit;
    # wineserver --wait
  '';
}
