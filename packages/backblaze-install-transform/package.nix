{ lib
, backblaze-installer
, fetchurl
, fetchzip
, runCommand
, wineWowPackages # 32+64 bit wine
, winetricks
}:
let
  wine = wineWowPackages.stable;

  powershellWindows = fetchurl {
    url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-arm64.msi";
    sha256 = "0yd0wdacv2f5fl345vbnrvgxgbky0g2z2fl9ip9j003yyk8lk9hn";
  };

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

  transform = runCommand "generate-backblaze-install-transform" { buildInputs = [ wine ]; } ''
    mkdir home
    export HOME="$(realpath home)"

    export WINEARCH="win64"
    export WINEDLLOVERRIDES="mscoree=" # Disable Mono installation
    export WINEDEBUG=+all

    wineboot --init

    cp ${winInstallerNuget}/lib/net20/WixToolset.Dtf.WindowsInstaller.dll "''${HOME}"/.wine/drive_c/WixToolset.Dtf.WindowsInstaller.dll
    cp ${./mst-generate.ps1} "''${HOME}"/.wine/drive_c/mst-generate.ps1
    cp ${backblaze-installer} "''${HOME}"/.wine/drive_c/bzinstall.msi

    msiexec /i ${powershellWindows} ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 /q

    # wine64 powershell.exe -NoProfile -Noninteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File c:\mst-generate.ps1
    # cp "''${HOME}"/.wine/drive_c/bzinstall.mst "$out"
  '';
in
transform
