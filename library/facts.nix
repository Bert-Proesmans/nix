_lib:
{
  # NOTE; The "locally administrated"-bit must be set for generated MAC addresses to make the change of random collision impossible!
  # REF; https://www.hellion.org.uk/cgi-bin/randmac.pl
  facts = {
    # WARN; This is the same filepath as defined in tasks.py!
    sops.keypath = "/etc/secrets/decrypter.age";

    buddy.net.physical.mac = "b4:2e:99:15:33:a6";
    buddy.net.management.mac = "4a:5c:7c:d1:8a:35";
    #buddy.net.management.ipv4 = "192.168.88.10";

    #vm.dns.net.mac = "4e:72:72:20:a5:2f";
    vm.idm.net.mac = "9e:30:e8:e8:b1:d0";
  };
}
