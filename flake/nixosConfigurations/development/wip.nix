{ lib, flake, pkgs, config, ... }:
{
  sops.secrets.crowdsec-apikey.owner = "crowdsec";

  imports = [ flake.inputs.crowdsec.nixosModules.crowdsec ];
  services.crowdsec =
    let
      # NOTE; Derived from upstream module config
      configDir = "/var/lib/crowdsec/config";
    in
    {
      enable = true;
      enrollKeyFile = config.sops.secrets.crowdsec-apikey.path;
      allowLocalJournalAccess = true;

      acquisitions = [{
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
        labels.type = "syslog";
      }];

      settings = {
        api.server.listen_uri = "127.0.0.1:8080";
        prometheus.enabled = false;
        config_paths = {
          # Setup a R/W path to dynamically enable/disable simulations.
          # SEEALSO; systemd.services.crowdsec.serviceConfig.ExecStartPre
          simulation_path = "${configDir}/simulation.yaml";
        };
        nftables = {
          ipv4 = {
            enabled = false;
            table = "firewall"; # Match networking.nftables.tables.<name>
            set-only = true;
          };
          ipv6 = {
            enabled = false;
            table = "firewall"; # Match networking.nftables.tables.<name>
            set-only = true;
          };
        };
      };
    };

  networking.nftables.enable = true;
  networking.nftables.tables = {
    # Disable default firewall ruleset
    nixos-fw.enable = false;

    firewall = {
      family = "inet"; # ipv4/6 combined
      content = ''
        # NOTE; set name is hardcoded
        set crowdsec-blacklists {
          type ipv4_addr
          flags timeout
        }

        # NOTE; set name is hardcoded
        set crowdsec6-blacklists {
          type ipv6_addr
          flags timeout
        }

        chain bouncer {
          # Hook as early as possible to keep packet processing load light.
          type filter hook prerouting priority raw; policy accept;

          ip saddr @crowdsec-blacklists drop
          ip6 saddr @crowdsec6-blacklists drop
        }

        chain rpfilter {
          # Hook running right after (connection tracking and) mangle to incorporate packet marks into route decision.
          type filter hook prerouting priority mangle + 10; policy drop;

          fib saddr . mark . iif oif exists accept comment "allow valid reverse path"
          jump rpfilter-exceptions comment "test for exceptions, then come back here"
        }

        chain rpfilter-exceptions {
          meta nfproto ipv4 udp sport . udp dport { 67 . 68, 68 . 67 } accept comment "DHCPv4 client/server"
        }

        chain input {
          type filter hook input priority filter; policy drop;
        
          iifname { lo } accept
          ct state {established, related} accept
          ct state invalid drop
        
          # Internet control messages (ICMP) (minimal set for a server)
          # routers may also want: mld-listener-query, nd-router-solicit
          ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept comment "allow ICMP"
          ip protocol icmp icmp type { destination-unreachable, router-advertisement, time-exceeded, parameter-problem } accept comment "allow ICMP"
        
          ip6 nexthdr icmpv6 icmpv6 type echo-request accept comment "allow ping"
          ip protocol icmp icmp type echo-request accept comment "allow ping"
        
          tcp dport { ${toString (lib.head config.services.openssh.ports)} } accept comment "allow ssh"

          # <=> (tcp_flags & (fin | syn | rst | ack)) == syn, only match on exactly "SYN"
          tcp flags syn / fin,syn,rst,ack log level info prefix "refused connection: "
          counter drop comment "drop (count) other traffic)"
        }

        set temp-ports {
          comment "Temporarily opened ports"
          type inet_proto . inet_service
          flags interval
          auto-merge
        }

        chain input-accept {
          # Fixed and dynamic rules for accepting incoming traffic

          tcp dport { ${lib.concatMapStringsSep "," toString (config.networking.firewall.allowedTCPPorts ++ config.networking.firewall.allowedTCPPortRanges)} } accept
          # udp dport { ${lib.concatMapStringsSep "," toString (config.networking.firewall.allowedUDPPorts ++ config.networking.firewall.allowedUDPPortRanges)} } accept
          meta l4proto . th dport @temp-ports accept comment "temporary ports, use nft add element inet filter temp-ports { tcp . 12345, udp . 23456 }"
        }
        
        chain output {
          type filter hook output priority filter; policy drop;
          
          accept comment "allow all outgoing connections"
        }
        
        chain forward {
          type filter hook forward priority filter; policy drop;
          
          drop comment "no forwarding, this is not a router"
        }
      '';
    };
  };

  systemd.services.crowdsec.serviceConfig = {
    ExecStartPre =
      let
        installConfigurations = pkgs.writeShellApplication {
          name = "install-configurations";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path;
          text = ''
            # WARN; Required on first run to hydrate the hub index
            # Is executed by the upstream ExecStartPre script!
            # cscli hub upgrade

            ## Collections
            cscli collections install \
              crowdsecurity/linux

            ## Parsers
            # Whitelists private IPs
            # if ! cscli parsers list | grep -q "whitelists"; then
            #     cscli parsers install crowdsecurity/whitelists
            # fi

            ## Heavy operations
            cscli postoverflows install \
              crowdsecurity/ipv6_to_range \
              crowdsecurity/rdns

            ## Non-actionable scenario's
            echo 'simulation: false' >'${config.services.crowdsec.settings.config_paths.simulation_path}'
            cscli simulation enable crowdsecurity/http-bad-user-agent
            cscli simulation enable crowdsecurity/http-crawl-non_statics
            cscli simulation enable crowdsecurity/http-probing
          '';
        };
      in
      lib.mkAfter [ (lib.getExe installConfigurations) ];
    ExecStartPost =
      let
        waitForStart = pkgs.writeShellApplication {
          name = "wait-for-start";
          # ERROR; crowdsec cli tool is wrapped with setting arguments, we need those!
          runtimeInputs = config.systemd.services.crowdsec.path ++ [ pkgs.coreutils ];
          text = ''
            while ! nice -n19 cscli lapi status; do
              echo "Waiting for CrowdSec daemon to be ready"
              sleep 10
            done
          '';
        };
      in
      lib.mkBefore [ (lib.getExe waitForStart) ];
  };
}
