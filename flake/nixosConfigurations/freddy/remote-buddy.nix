{
  lib,
  pkgs,
  config,
  ...
}:
let
  ip-buddy = config.proesmans.facts.buddy.host.tailscale.address;
  fqdn-buddy = "buddy.internal.proesmans.eu";
in
{
  sops.secrets."buddy_ssh" = { };

  programs.ssh.knownHosts = {
    "buddy".hostNames = [ fqdn-buddy ];
    "buddy".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICj+WUMawU/pZ8yGJNeoL8vsc5B+LOi4Y7JTCG4bv4vp";
  };

  # Make sure the fqdn of buddy resolves through tailscale!
  networking.hosts."${ip-buddy}" = [ fqdn-buddy ];

  systemd.targets."buddy-online" = {
    description = "Buddy is online";
  };

  systemd.services."buddy-online-tester" = {
    description = "Ping buddy";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.systemd # systemctl
      pkgs.iputils # ping
    ];
    enableStrictShellChecks = true;
    script = ''
      state="unknown"

      while true; do
        # Want 3 ping replies within 10 seconds awaiting each response for 2 seconds after request.
        if ping -c 3 -w 10 -W 2 "${config.proesmans.facts.buddy.host.tailscale.address}" >/dev/null; then
          new_state="online"
        else
          new_state="offline"
        fi

        if [ "$new_state" != "$state" ]; then
          if [ "$new_state" = "online" ]; then
            systemctl start "${config.systemd.targets.buddy-online.name}"
            echo "AVAILABLE transition" >&2
          else
            systemctl stop "${config.systemd.targets.buddy-online.name}"
            echo "OFFLINE transition" >&2
          fi

          state="$new_state"
        fi

        if [ "$state" = "online" ]; then
          # check less often when stable
          sleep 60
        else
          # retry faster when buddy is offline
          sleep 10
        fi
      done
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = 60;
    };
  };

}
