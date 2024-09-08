{ callPackage
, lib
, stdenv
, fetchFromGitHub
, fetchurl
, nixos
, testers
, versionCheckHook
, netcat-openbsd
, gnugrep
, coreutils
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "unsock";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "kohlschutter";
    repo = "unsock";
    rev = "51bf1492f91d9bce68bb16a84087d8a4a75604b6";
    hash = "sha256-3VbycUrGeIQWzx8gOeXlR38FhH+ny+uooH/THKKnfZw=";
  };

  makeFlags = [ "PREFIX=$(out)" ];

  doCheck = true;
  nativeCheckInputs = [ netcat-openbsd gnugrep coreutils ];

  postInstall = ''
    mkdir $out/bin
    ln --symbolic $out/lib/libunsock.so $out/bin/libunsock.so
  '';

  meta = {
    description = "Shim library to automatically change AF_INET sockets to AF_UNIX, etc.";
    longDescription = ''
      Unix domain sockets (`AF_UNIX`) are Berkeley (BSD-style) sockets that are accessible
      as paths in the file system. Unlike `AF_INET` sockets, they may be given user and group
      ownership and access rights, which makes them an excellent choice to connect services
      that run on the same host. 

      Unfortunately, not all programs support Unix domain sockets out of the box. This is
      where *unsock* comes in:

      *unsock* is a shim library that intercepts Berkeley socket calls that
      use `AF_INET` sockets and automatically rewrites them such that they use `AF_UNIX` sockets instead,
      without having to modify the target program's source code.

      Moreover, with the help of a custom control file in place of a real `AF_UNIX` domain socket,
      unsock allows communicating over all sorts of sockets, such as `AF_VSOCK` and `AF_TIPC`.

      Using *unsock* not only makes systems more secure (by not having to expose internal communication
      as `AF_INET` sockets), it also helps improve performance by removing inter-protocol proxies from
      the equation — programs can now talk directly to each other.

      *unsock* specifically also simplifies communication between a virtual machine and its host, by
      allowing communication to go through `AF_VSOCK` sockets even if the programs were designed for
      IPv4-communication only. As a bonus feature, *unsock* simplifies communication with
      [Firecracker-style](https://github.com/firecracker-microvm/firecracker/blob/main/docs/vsock.md)
      multiplexing sockets.

    '';
    homepage = "https://github.com/kohlschutter/unsock";
    changelog = "https://github.com/kohlschutter/unsock/releases/tag/unsock-${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = [ ];
    # Executable for creating socket config files
    mainProgram = "libunsock.so";
    platforms = lib.platforms.linux;
  };
})