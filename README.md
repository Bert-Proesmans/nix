# Bert's Nix

I hate to do it to you, but go look into the [flake subdirectory](./flake) for the information you came for.

## Setup

At the end of these steps you'll have a Hyper-V virtual machine running the development machine configuration.  
High level approach; Create the virtual machine, boot the bootstrap ISO, download and install the development host configuration.

1. Download boot/install ISO for the development host from the [repository releases page](https://github.com/Bert-Proesmans/nix/releases)
1. Setup a new hyper-v virtual machine on your machine, refer to the script [hyperv-vm.ps1](./documentation/hyperv-vm.ps1)
1. Bootstrap
  1. Boot VM from ISO
  1. Clone repository; `git clone https://github.com/Bert-Proesmans/nix.git`
  1. Open development environment; `cd nix && nix develop`
  1. Set (nixos) user password; `passwd`
  1. Install system; `invoke deploy development localhost`
      * You'll be asked to provide the password created in the previous step
  1. Reboot VM without ISO
1. In your windows environment, add a configuration block to the SSH config file (typically found at `C:\Users\<UserName>\.ssh\config`)
```ssh_config
Host local-development
  HostName fde0:5584:ba8e::139
  User <your-user-name>
  ForwardAgent yes
```
1. In your windows environment, test SSH connectivity
  1. ping fde0:5584:ba8e::139
  1. ssh local-development
  1. Trust the SSH host-key of your local-development virtual machine
1. Connect to your development machine and update once to the most recent version
  See "Maintain your development machine" below
DONE

> [!IMPORTANT]  
> You **must** trust the host key once interactively!
> Both VSCode and Git will hang on this question, if not previously marked as trusted, because they execute non-interactive processes in the background.
