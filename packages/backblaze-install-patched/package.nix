{ lib
, backblaze-installer
, fetchurl
, fetchzip
, runCommand
, wineWowPackages # 32+64 bit wine
, winetricks
}:
let
  wine = wineWowPackages.stableFull; # Need embedded mono installer!

  winInstallerNuget = fetchzip {
    url = "https://www.nuget.org/api/v2/package/WixToolset.Dtf.WindowsInstaller/5.0.2";
    stripRoot = false;
    extension = "zip";
    # nix-prefetch-url --unpack <URL>
    # Defaults to outputting sha256 hash.
    # Note that the installer is not version pinned! Only when the hash is manually changed a redownload will occur
    # (or a nix garbage collect has run)
    sha256 = "17xk799yzykk2wjifnwk2dppjkrwb8q6c70gsf7rl8rw7q7l1z5v";
  };

  # ERROR; Do _not_ just use the latest powershell. The version below is pinned from winetricks and works.
  powershellWindows = fetchurl {
    url = "https://github.com/PowerShell/PowerShell/releases/download/v7.2.21/PowerShell-7.2.21-win-x64.msi";
    sha256 = "1ba65dn1dzb7ihkdllhbh876zckl3n5yca92i73nxml93jql0xj0";
  };

  transform = runCommand "generate-backblaze-install-transform" { buildInputs = [ wine ]; } ''
    mkdir home
    export HOME="$(realpath home)"

    export WINEARCH="win64"
    export WINEDLLOVERRIDES=""
    
    # Uncomment WINEDEBUG to get more insight into what is happening. Printing more debug information slows down the build duration!
    # export WINEDEBUG=+all
    # export WINEDEBUG=+process

    wineboot --init

    cp ${backblaze-installer} "''${HOME}"/.wine/drive_c/bzinstall.msi
    cp ${winInstallerNuget}/lib/net20/WixToolset.Dtf.WindowsInstaller.dll "''${HOME}"/.wine/drive_c/WixToolset.Dtf.WindowsInstaller.dll
    cp ${./inplace-fix.ps1} "''${HOME}"/.wine/drive_c/inplace-fix.ps1

    wine msiexec /quiet /i ${powershellWindows} ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1

    # wine "C:\Program Files\PowerShell\7\pwsh.exe" -c "Echo test hello hello" | tee "$out"
    wine "C:\Program Files\PowerShell\7\pwsh.exe" -Noninteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File c:\inplace-fix.ps1
    
    cp "''${HOME}"/.wine/drive_c/bzinstall-finished.msi "$out"
  '';
in
transform
