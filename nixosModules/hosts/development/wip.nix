{ lib, pkgs, config, ... }: {

  proesmans.vsock-proxy.proxies = [
    {
      # Setup http-server on 127.0.0.1:9585
      # <- receives from listening VSOCK
      # <- receives packet from guest VM
      listen.vsock.cid = 2;
      listen.port = 8080;
      transmit.tcp.ip = "127.0.0.1";
      transmit.port = 9585;
    }
  ];

}
