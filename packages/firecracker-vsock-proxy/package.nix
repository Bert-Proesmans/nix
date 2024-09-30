{ lib
, python3Packages
}:
let
  pname = "firecracker-vsock-proxy";
in
python3Packages.buildPythonApplication {
  inherit pname;
  version = "0.0.0";
  format = "other";

  propagatedBuildInputs = [
    # List of dependencies
  ];

  # Do direct install
  dontUnpack = true;
  installPhase = ''
    install -Dm755 ${./firecracker-proxy.py} $out/bin/${pname}
  '';

  meta = with lib; {
    description = "Connect with a VSOCK firecracker-style";
    mainProgram = pname;
    platforms = platforms.linux;
  };
}
