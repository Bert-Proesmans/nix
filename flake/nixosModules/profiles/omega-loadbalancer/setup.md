# Boot on AMD one(1) OCPU

## Automated install instructions

WARN; Due to limited available RAM, copying the system could seemingly hang (shared VPS resources, effects vary).
Normally the host will get through everything, it just takes some time. If kswapd0 starts to use >15% CPU usage over >10seconds,
cancel the deploy and retry.

1. Reduce RAM on VPS
    1. sudo systemctl --no-block stop snapd snap* unattended-upgrades
    2. echo 3 | sudo tee /proc/sys/vm/drop_caches
2. Kernel exec (K'exec) into nixos system
    - curl -L https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /tmp && sudo /tmp/kexec/run
1. Run deploy task to prepare and install host
    - invoke deploy 01-fart root@<$IP> --password-request
INSTRUCTIONS FINISHED.

## Manual install instructions

NOTE; nixos-anywhere should be able to "stream-install" as well in limited RAM circumstances. The instructions below are doing
the manual work for minimal RAM impact.

1. Configure VPS
    1. Choose a minimal ubuntu image
    2. Enter SSH pubkey
2. SSH into host (ssh ubuntu@<$IP>)
3. Cleanup running processes to free RAM (`top`, press e, press shift+m)
    1. sudo systemctl --no-block stop snapd snap* unattended-upgrades
    2. echo 3 | sudo tee /proc/sys/vm/drop_caches
4. Kernel exec (K'exec) into nixos system
    - curl -L https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /tmp && sudo /tmp/kexec/run
5. SSH into kexec (ssh root@<$IP>), or use console connection
6. Build and copy format script of host
    1. nix build --no-link ./flake#nixosConfigurations.01-fart.config.system.build.diskoScript
    2. DISKO="$(nix path-info ./flake#nixosConfigurations.01-fart.config.system.build.diskoScript)"
    3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP" "$DISKO" --no-check-sigs
7. Execute format script
    1. ssh "root@$IP" "$DISKO"
NOTE; Disko leaves the new root filesystem mounted at /mnt
8. Install the nixos configuration
    1. nix build --no-link ./flake#nixosConfigurations.01-fart.config.system.build.toplevel
    2. HOST="$(nix path-info ./flake#nixosConfigurations.01-fart.config.system.build.toplevel)"
    WARN; nixos-install has two modes; 1. build the target system from sources (in nix store) / 2. copy built system from a local nix store
        But we cannot build on FART and we're running completely from RAM (aka no persistent attached storage to boot NixOS from).
        So;
        - The built system is copied into /mnt(/nix) using the remote-store feature.
        - nixos-install is called with a root argument to assume '/nix/store' as '/mnt/nix/store' and install correctly
    ERROR; The nix copy operation could hang due to kernel swapping, if it looks like progress stalled
           cancel the command and wait for the swapping to end. Then execute the same command again.
    3. nix copy --substitute-on-destination --to "ssh-ng://root@$IP?remote-store=/mnt&" "$HOST" --no-check-sigs
    4. ssh "root@$IP" nixos-install --no-root-password --no-channel-copy --root /mnt --system "$HOST"
    9. Reboot system; ssh "root@$IP" reboot
INSTRUCTIONS FINISHED.