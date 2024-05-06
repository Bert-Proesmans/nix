import os
from pathlib import Path
from typing import Any, Union
from shlex import quote
import subprocess
from tempfile import TemporaryDirectory
import json

# REF; https://www.pyinvoke.org/
from invoke import task
# REF; https://github.com/numtide/deploykit/
from deploykit import DeployHost


INVOKED_PATH = Path.cwd()

FLAKE = Path(__file__).parent.resolve()
os.chdir(FLAKE)

@task
# USAGE: invoke check
def check(c: Any) -> None:
    """
    Evaluate and build all outputs from the flake common schema, including all attribute sets from the output 'checks'.
    This command does not stop executing after encountering an error, and will run until all tasks have ended.
    """
    c.run("nix flake check --keep-going")

@task
# USAGE: invoke check
def format(c: Any) -> None:
    """
    Format the source code of this repository.
    """
    c.run("nix fmt")

@task
def update_sops_files(c: Any) -> None:
    """
    Update all sops yaml files according to .sops.yaml rules
    """
    environment = os.environ.copy()
    subprocess.run(
        """
        find . -type f \\( -iname '*.encrypted.yaml' \\) -print0 | \
        xargs -0 -n1 sops updatekeys --yes
        """
        , env=environment, shell=True, check=True
    )

def private_opener(path: str, flags: int) -> Union[str, int]:
    return os.open(path, flags, 0o400)

def decrypt_host_key(flake_attr: str, tmpdir: str) -> None:
    # Location of encrypted keys for the specified system configuration
    keys_file = FLAKE / "nixosModules" / "hosts" / flake_attr / "keys.encrypted.yaml"

    # Prepare filepath and secure file access to store sensitive key material
    tmp = Path(tmpdir)
    tmp.mkdir(parents=True, exist_ok=True)
    tmp.chmod(0o755)
    host_key = tmp / "etc/ssh/ssh_host_ed25519_key"
    host_key.parent.mkdir(parents=True, exist_ok=True) 

    with open(host_key, "w", opener=private_opener) as key_handle:
        environment = os.environ.copy()
        environment["SOPS_AGE_KEY"] = decrypt_dev_key()

        # Decrypt the keys file, extract the value of key 'ssh_host_ed25519_key', push the decrypted value
        # to stdout, redirect stdout to the file at /tmp
        #
        # ERROR; Explicit program and argument syntax (list/bracket form), because we're not using
        # the shell as intermediate command interpreter
        subprocess.run(
            [
                'sops'
                , '--extract'
                , '["ssh_host_ed25519_key"]'
                , '--decrypt'
                , quote(keys_file.as_posix())
            ]
            , env=environment
            , check=True
            , stdout=key_handle
        )

@task
# USAGE; invoke deploy --flake-attr development --hostname 10.1.7.100
def deploy(c: Any, flake_attr: str, hostname: str) -> None:
    """
    Decrypt the private SSH hostkey of the target machine, deploy the machine, upload the private hostkey to
    the host filesystem.
    Use this command to do initial configuration (aka installation) of new hosts.
    """
    ask = input(f"Install configuration {flake_attr} on {hostname}? [y/N] ")
    if ask != "y":
        return

    with TemporaryDirectory() as tmpdir:
        decrypt_host_key(flake_attr, tmpdir)

        deploy_flags = "--debug"
        #deploy_flags += " --no-reboot"
        
        # NOTE; Flakes can give hints to the nix CLI to change runtime behaviours, like adding a binary cache for
        # operations on that flake execution only.
        # These options are encoded inside the 'nixConfig' output attribute of the flake-schema.
        # REF; https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-format
        #
        #deploy_flags += " --option accept-flake-config true"
        
        environment = os.environ.copy()
        # ERROR; Cannot use sops --exec-file because we need to pass a full file structure to nixos-anywhere
        subprocess.run(
            f"""
            nix run nixpkgs#nixos-anywhere -- {hostname} --extra-files {tmpdir} --flake .#{flake_attr} {deploy_flags}
            """
            , env=environment, shell=True, check=True
        )

@task
# USAGE; invoke secret-edit nixosModules/hosts/development/secrets.yaml
def secret_edit(c: Any, file_path: str) -> None:
    """
    Load the decryption key from the keyserver, decrypt the development key, start sops to edit the plaintext secrets of the provided file
    """

    # WARN; Path to existing file (for editing), or path to non-existant file for creation by SOPS.
    encrypted_file = (INVOKED_PATH / file_path).absolute()
    assert encrypted_file.name.endswith("encrypted.yaml"), """
        The convention is to end the filename of encrypted sensitive content with *.encrypted.yaml.
        Update the provided path argument to align with the above convention!
    """

    environment = os.environ.copy()
    subprocess.run(f"sops \"{quote(encrypted_file.as_posix())}\"", env=environment, shell=True, check=True)

@task
# USAGE; invoke create-host-key nixosModules/hosts/development/keys.encrypted.yaml
def create_host_key(c: Any, file_path: str) -> None:
    """
    Create and encrypt a new SSH private host key.
    Use this command when defining a new host configuration. This is a required step before executing `invoke deploy <host>`.
    """
    
    # WARN; Path to existing file (for editing), or path to non-existant file for creation by SOPS.
    encrypted_file = (INVOKED_PATH / file_path).absolute()
    assert encrypted_file.name.endswith("encrypted.yaml"), """
        The convention is to end the filename of encrypted sensitive content with *.encrypted.yaml.
        Update the provided path argument to align with the above convention!
    """

    assert not encrypted_file.exists(), """
        The designated file to store the encrypted key material already exists. This task will not overwrite that file!
        If it's intentional to overwrite the host key, delete the encrypted file and retry.
    """

    with TemporaryDirectory() as tmpdir:
        # Prepare filepath and secure file access to store sensitive key material
        tmp = Path(tmpdir)
        tmp.mkdir(parents=True, exist_ok=True)
        tmp.chmod(0o755)
        host_key = tmp / "ssh_host_ed25519_key"
        pub_host_key = host_key.with_suffix(".pub")
        file_to_encrypt = tmp / "keys.json"

        # Create a new key of type 'ed25519', written to the designated filepath
        #
        # ERROR; Explicit program and argument syntax (list/bracket form), because we're not using
        # the shell as intermediate command interpreter
        subprocess.run(
            [
                'ssh-keygen'
                , '-t', 'ed25519'
                , '-N', '' # No password
                , '-f', host_key.as_posix()
            ]
            , check=True
        )

        # Write out a json file with the key material
        with open(host_key, "r", opener=private_opener) as key_handle:
            with open(file_to_encrypt, "w", opener=private_opener) as to_encrypt_handle:
                data = {"ssh_host_ed25519_key": key_handle.read()}
                json.dump(data, to_encrypt_handle)
        
        # Encrypt the json file with SOPS
        # ERROR; It's not possible to programmatically instruct sops to create an encrypted file with exact contents.
        # The argument is that sops is not a secrets manager, but a secrets editor..
        subprocess.run(
            [
                'sops'
                , '--encrypt'
                , '--input-type', 'json'
                # WARN; Explicit conversion json->yaml because I don't want to pull in a python library to
                # process yaml files correctly.. sops can do this :D
                , '--output-type', 'yaml'
                , '--output', encrypted_file.as_posix() # Write directly into the output file
                # Input file
                , file_to_encrypt.as_posix()
            ]
            , check=True
        )

        c.run(f'echo "AGE PUB KEY to use in sops config"; cat "{quote(pub_host_key.as_posix())}" | ssh-to-age')
        print(
            """
            Insert the age-key into the sops.yaml file,
            and follow up `invoke update-sops-files` to rekey the encrypted files
            """
        )
