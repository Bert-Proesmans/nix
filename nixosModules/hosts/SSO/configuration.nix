{ lib, pkgs, profiles, config, ... }: {

  imports = [
    ./provision.nix # Setup users/groups/applications
  ];

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

  environment.systemPackages = [
    # Add CLI tools to PATH
    pkgs.kanidm
  ];

  services.kanidm =
    let
      unit-name = config.systemd.services.kanidm.name;
    in
    {
      enableServer = true;
      # NOTE; Custom patches required to pre-provision secret values like;
      #   - admin account passwords
      #   - oauth2 basic secrets
      package = pkgs.kanidm.withSecretProvisioning;
      serverSettings = {
        bindaddress = "0.0.0.0:443"; # Requires CAP_NET_BIND_SERVICE
        domain = "idm.proesmans.eu";
        origin = "https://idm.proesmans.eu";
        db_fs_type = "zfs";
        role = "WriteReplica";
        online_backup.enabled = false;

        # Path prefix '/run/credentials/<unit name>/' is expanded value of '%d' and
        # '$CREDENTIALS_DIRECTORY' aka SystemD credentials directory.
        # SEEALSO; systemd.services.kanidm.serviceConfig.LoadCredential`
        #
        # NOTE; These certificate paths are automatically added as read-only bind paths
        # by the upstream nixos module. The binding doesn't seem to have any impact on
        # the credentials infrastructure.
        tls_chain = "/run/credentials/${unit-name}/FULLCHAIN_PEM";
        tls_key = "/run/credentials/${unit-name}/KEY_PEM";
      };

      provision.idmAdminPasswordFile = "/run/credentials/${unit-name}/IDM_PASS";
    };

  systemd.services.kanidm = {
    serviceConfig = {
      LoadCredential = [
        # WARN; Certificate files must be loaded into the unit credential store because
        # the original files require root access. This unit executes with user kanidm permissions.
        "FULLCHAIN_PEM:/data/certs/fullchain.pem"
        "KEY_PEM:/data/certs/key.pem"
        "IDM_PASS:/seeds/idm_admin_password"
      ];
    };
  };

  # A crude approach to linking state between hypervisor provided path and systemd service that
  # is permission compatible. Systemd will update the permissions for user kanidm on path
  # /var/lib/kanidm -[coalesced]-> /data/state -[coalesced]-> (hypervisor) /vm/kanidm.
  systemd.mounts = [{
    what = "/data/state";
    where = "/var/lib/kanidm";
    type = "none";
    options = "bind";
    requiredBy = [ config.systemd.services.kanidm.name ];
  }];

  # Ignore below
  # Consistent defaults accross all machine configurations.
  system.stateVersion = "24.05";
}
