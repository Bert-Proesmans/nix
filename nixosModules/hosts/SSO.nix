{ lib, pkgs, profiles, config, ... }: {
  services.openssh.hostKeys = [
    {
      path = "/seeds/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd.services.sshd.unitConfig.ConditionPathExists = "/seeds/ssh_host_ed25519_key";

  # DEBUG
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;
  users.users.bert-proesmans.extraGroups = [ "wheel" ];
  # DEBUG

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 443 ];

  services.kanidm = {
    enableServer = true;
    serverSettings = {
      bindaddress = "0.0.0.0:443"; # Requires CAP_NET_BIND_SERVICE
      domain = "idm.proesmans.eu";
      origin = "https://idm.proesmans.eu";
      db_fs_type = "zfs";
      role = "WriteReplica";
      online_backup.versions = 0; # disable online backup

      # Path prefix '/run/credentials/<unit name>/' is expanded value of '%d' and
      # '$CREDENTIALS_DIRECTORY' aka SystemD credentials directory.
      # SEEALSO; systemd.services.kanidm.serviceConfig.LoadCredential`
      #
      # NOTE; These certificate paths are automatically added as read-only bind paths
      # by the upstream nixos module.
      tls_chain = "/run/credentials/kanidm/FULLCHAIN_PEM";
      tls_key = "/run/credentials/kanidm/KEY_PEM";
    };
  };

  systemd.services.kanidm = {
    serviceConfig = {
      LoadCredential = [
        # WARN; Certificate files must be loaded into the unit credential store because
        # the original files require root access. This unit executes with user kanidm permissions.
        "FULLCHAIN_PEM:/data/certs/fullchain.pem"
        "KEY_PEM:/data/certs/key.pem"
      ];
    };
  };

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
