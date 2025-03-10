{
  services.dns = {
    ipAddresses = [ ];
  };

  hosts.development = {
    hostname = "development";
    domain = "internal.proesmans.eu";
    tags = [ "virtual-machine" "hypervisor" ];
  };

  # TODO
}
