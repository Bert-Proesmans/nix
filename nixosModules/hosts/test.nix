{ lib, pkgs, config, ... }: {
  networking.domain = "alpha.proesmans.eu";

  environment.systemPackages = [
    pkgs.socat
    pkgs.tcpdump
    pkgs.python3
    pkgs.nmap # ncat
  ];

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];

  services.openssh.hostKeys = [
    {
      path = "/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";
  systemd.services.sshd.serviceConfig.StandardOutput = "journal+console";

  system.stateVersion = "24.05";
}
