{ lib, pkgs, commonNixosModules, outputs, ... }:
let
  snakeOilPrivateKeyFile = pkgs.writeText "privkey.snakeoil" ''
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIHQf/khLvYrQ8IOika5yqtWvI0oquHlpRLTZiJy5dRJmoAoGCCqGSM49
    AwEHoUQDQgAEKF0DYGbBwbj06tA3fd/+yP44cvmwmHBWXZCKbS+RQlAKvLXMWkpN
    r1lwMyJZoSGgBHoUahoYjTh9/sJL7XLJtA==
    -----END EC PRIVATE KEY-----
  '';

  snakeOilPublicKey = lib.concatStrings [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHA"
    "yNTYAAABBBChdA2BmwcG49OrQN33f/sj+OHL5sJhwVl2Qim0vkUJQCry1zFpKTa"
    "9ZcDMiWaEhoAR6FGoaGI04ff7CS+1yybQ= snakeoil"
  ];
in
lib.mapAttrs'
  (name: nixos-module: lib.nameValuePair "${name}-test"
    # Create a virtual machine fleet and virtual network that is subjected to the python testscript.
    # REF; https://nixos.org/manual/nixos/stable/index.html#sec-calling-nixos-tests
    (
      lib.nixos.runTest
      {
        name = "${name}-test";
        hostPkgs = pkgs;
        # ERROR; Cannot define nodes with nixosSystem attribute sets! We must use a toplevel nixosModule
        # because the testing framework expects to be able to build its own nixosSystem (with additional custom options).
        nodes =
          {
            server = { lib, ... }: {
              imports = commonNixosModules ++ [ nixos-module ];

              virtualisation.cores = 2;
              virtualisation.memorySize = 2048;
              virtualisation.graphics = false;
              users.users.root.openssh.authorizedKeys.keys = [
                snakeOilPublicKey
              ];

              # REF; https://github.com/nix-community/srvos/blob/7c02fb006bdd70474853e6395bd5916ba2404fa2/nixos/common/networking.nix
              systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
              systemd.network.wait-online.enable = lib.mkForce false;
              # ERROR; The configuration defined hostName will affect the testscript variable naming.
              # We explicitly override the hostname to set node name 'server' everywhere.
              # networking.hostName => gets written to /etc/hosts for all nodes
              # system.name (<- networking.hostName) => gets used as variable in the test script for this node
              networking.hostName = lib.mkForce "server";
              networking.domain = lib.mkForce null;
            };
            client = { ... }: { virtualisation.graphics = false; };
          };

        # REF; https://nixos.org/manual/nixos/stable/index.html#ssec-machine-objects
        testScript = ''
          start_all()
          # The following command triggers an interactive shell on machine "server". Do not use this, rather
          # build the test-driver seperately and run a single test at once interactively.
          # See flake#checks description.
          # server.shell_interact()
          # NOTE; All timeout values are in unit "retries", this closely resembles amount of seconds
          # because retries are paused with 1 second sleep in between
          server.wait_for_unit("sshd.service", timeout=60)
          server.wait_for_open_port(22, timeout=5)
              
          # Wait for system OK is a lie
          # The multi-user target is not guaranteed to timely finish, aka it hangs sporadically
          # server.wait_for_unit("multi-user.target", timeout=60)
          # client.wait_for_unit("multi-user.target", timeout=60)

          # client has no private keys configured so calling out to server should fail
          client.fail("ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null server whoami")

          # install private key
          client.succeed("mkdir -p ~/.ssh")
          client.copy_from_host_via_shell("${snakeOilPrivateKeyFile}", "~/.ssh/id_ed25519")
          client.succeed("chmod 600 ~/.ssh/id_ed25519")

          # Make sure the output is the root user server
          ssh_user = client.succeed("ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null server whoami")
          # ERROR; Shell output is often appended with a newline! Strip whitespace before comparison.
          assert "root" == ssh_user.strip(), "SSH user is not root!"
        '';
      }
    ))
  outputs.nixosModules.hosts
