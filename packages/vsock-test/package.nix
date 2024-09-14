{ lib
, stdenv
, gcc
}:
stdenv.mkDerivation {
  pname = "vsock-test";
  version = "1.0";

  # Source files for the program
  src = ./.;

  buildInputs = [ gcc ];

  buildPhase = ''
    gcc -o vsock-test vsock-test.c
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp vsock-test $out/bin/
  '';

  meta = {
    description = "A simple C program for testing sibling vsock connectivity";
  };
}
