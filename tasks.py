import os
from pathlib import Path
from typing import Any, Union
import subprocess
from tempfile import TemporaryDirectory
import json
import warnings
import platform

# REF; https://www.pyinvoke.org/
from invoke import task
# REF; https://github.com/numtide/deploykit/


INVOKED_PATH = Path.cwd()

PROJECT_DIR = Path(__file__).parent.resolve()
os.chdir(PROJECT_DIR)

FLAKE = PROJECT_DIR / "flake"
DEV_KEY = (FLAKE / "source" / "development.age").absolute()


def alert_finish():
    # Riiiing my bell ! Ring my bell ! TINGELINGELING
    print("\a")


def ask_user_input(message: str) -> bool:
    user_reply = input(f"{message} [y/N]: ")
    return user_reply in ["yes", "y"]


def decryptor_encrypted_filename_default() -> str:
    return "keys.encrypted.yaml"


def decryptor_name_default(hostname: str) -> str:
    return f"{hostname}_decrypter"


def find_string_in_file(file_path, needle):
    try:
        with open(file_path, "r") as file:
            for line in file:
                if needle in line:
                    return True
        return False
    except FileNotFoundError:
        print(f"find_string_in_file: The file at {file_path} was not found.")
        raise
    except Exception as e:
        print(f"find_string_in_file: An error occurred: {e}")
        raise


def private_opener(path: str, flags: int) -> Union[str, int]:
    return os.open(path, flags, 0o400)


def dev_key_decrypt() -> str:
    assert DEV_KEY.exists(), """
        The encrypted development key is not found next to the tasks.py file!
    """

    warnings.warn("Decrypting the development key for usage!")
    age_key = subprocess.run(
        ["rage", "--decrypt", DEV_KEY.as_posix()],
        text=True,  # stdin/stdout are opened in text mode
        check=True,  # Throw exception if command fails
        capture_output=True,  # Redirect stdout/stderr
    ).stdout.strip()

    assert age_key, """
        Expected to decrypt an AGE private key, but decrypted an empty string. Something went unexpectedly wrong!
    """

    return age_key


@task
# USAGE: invoke check all|<hostName>
def check(c: Any, hostName: str) -> None:
    """
    Evaluate and build all outputs from the flake common schema, including all attribute sets from the output 'checks'.
    This command does not stop executing after encountering an error, and will run until all tasks have ended.
    """
    if "all" == hostName:
        # NOTE; --skip-cached skips realized outputs already present in binary caches!
        c.run(f"nix-fast-build --no-link --flake {FLAKE}#checks")
    else:
        c.run(
            f"nix-fast-build --no-link --flake {FLAKE}#nixosConfigurations.{hostName}.config.system.build.toplevel"
        )
    alert_finish()


@task
def ci(c: Any) -> None:
    """
    Similar to task 'check', but also builds the no-system jobs!
    """
    system = subprocess.run(
        ["nix", "eval", "--raw", "--impure", "--expr", "builtins.currentSystem"],
        text=True,  # stdin/stdout are opened in text mode
        check=True,
        capture_output=True,
    ).stdout.strip()

    # NOTE; --skip-cached skips realized outputs already present in binary caches!
    c.run(
        f'nix-fast-build --no-nom --skip-cached --no-link --flake "{FLAKE}#hydraJobs.{system}"'
    )

    if "x86_64-linux" == system:
        c.run(
            f"nix-fast-build --no-nom --skip-cached --no-link --flake '{FLAKE}#hydraJobs.no-system'"
        )
    alert_finish()


@task
# USAGE: invoke sops-files-update
def sops_files_update(c: Any) -> None:
    """
    Update all sops files according to .sops.yaml rules
    """
    environment = os.environ.copy()
    environment.pop("SOPS_AGE_KEY_FILE", None)
    environment["SOPS_AGE_KEY"] = dev_key_decrypt()

    subprocess.run(
        """
        find . -type f \\( -iname '*.encrypted.yaml' -o -iname '*.encrypted.yaml' \\) -print0 | \
        xargs -0 -n1 sops updatekeys --yes
        """,
        env=environment,
        shell=True,
        check=True,
    )


@task
# USAGE; invoke deploy development root@10.1.7.100 [-k "development_decrypter"]
def deploy(c: Any, hostname: str, ssh_connection_string: str, key: str = None) -> None:
    """
    Decrypts the secret used for sops-nix, deploys the machine, upload the secret to the host filesystem.
    """

    host_configuration_dir = FLAKE / "nixosModules" / "hosts" / hostname
    encrypted_file = host_configuration_dir / decryptor_encrypted_filename_default()

    assert host_configuration_dir.is_dir(), f"""
        There is no configuration folder found for host {hostname}.
        Create a nixos configuration at path `{host_configuration_dir.as_posix()}` first!
    """

    assert encrypted_file.is_file(), f"""
        There is no file containing decrypter keys.
        Create a decrypter key for host {hostname} first!
    """

    host_attr_path = (
        f"{FLAKE}#nixosConfigurations.{hostname}.config.system.build.toplevel"
    )

    print(f"Checking if host {hostname} builds..")
    subprocess.run(["nix", "build", host_attr_path, "--no-link"], check=True)

    if not ask_user_input(
        f"Install configuration {hostname} on {ssh_connection_string}?"
    ):
        return

    if not key:
        key = decryptor_name_default(hostname)
        warnings.warn(f"Defaulting to key name {key}")

    environment = os.environ.copy()
    environment.pop("SOPS_AGE_KEY_FILE", None)
    environment["SOPS_AGE_KEY"] = dev_key_decrypt()

    print(f"Decrypting AGE identity from {encrypted_file}:{key}..")
    age_key = subprocess.run(
        [
            "sops",
            "decrypt",
            "--extract",
            json.dumps([key]),
            encrypted_file.as_posix(),
        ],
        env=environment,
        text=True,  # stdin/stdout are opened in text mode
        check=True,
        capture_output=True,
    ).stdout.strip()

    assert age_key, """
        Expected decrypting an AGE private key, but decrypted an empty string. Something went unexpectedly wrong!
    """

    with TemporaryDirectory() as deploy_directory:
        # Prepare filepath and secure file access to store sensitive key material
        deploy_directory = Path(deploy_directory)
        deploy_directory.mkdir(parents=True, exist_ok=True)
        deploy_directory.chmod(0o755)
        decrypter_file_path = deploy_directory / "etc" / "secrets" / "decrypter.age"
        decrypter_file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(decrypter_file_path, "wt", opener=private_opener) as file_handle:
            file_handle.write(age_key)

        deploy_flags = [
            "--debug",
            #"--no-substitute-on-destination",
            # "--stop-after-disko", # DEBUG
            # "--no-reboot",
            # NOTE; Flakes can give hints to the nix CLI to change runtime behaviours, like adding a binary cache for
            # operations on that flake execution only.
            # These options are encoded inside the 'nixConfig' output attribute of the flake-schema.
            # REF; https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-format
            #
            # "--option accept-flake-config true",
        ]

        # NOTE; The (nixos-anywhere) default is to let the target pull packages from the caches first, and if they not exist there
        # the current (buildhost) host will push the packages.
        # There are more situations where uploading from current host first is desired, as opposed to downloading from
        # the internet caches!
        local_targets_marker = ["localhost", "127.0.0.1", "192.168."]
        if any(x in ssh_connection_string for x in local_targets_marker):
            # Since we have a populated nix store, and this is a local install; do not let the target pull from
            # the external nix caches.
            deploy_flags.append("--no-substitute-on-destination")

        # ERROR; Cannot use sops --exec-file because we need to pass a full file structure to nixos-anywhere
        subprocess.run(
            [
                "nixos-anywhere",
                "--extra-files",
                deploy_directory,
                "--flake",
                f"{FLAKE}#{hostname}",
            ]
            + deploy_flags
            + [ssh_connection_string],
            env=environment,
            check=True,
        )
        alert_finish()


@task
# USAGE; invoke filesystem-rebuild development
def filesystem_rebuild(c: Any, flake_attr: str) -> None:
    """
    Builds the disko format script, pushes it to the destination host and executes the script.
    This will attempt to realise the (presumably) changed configuration. This is only really useful when
    new ZFS datasets were added, or empty disk space is now taken in with new partition(s).

    This operation should happen **before** a nixos-rebuild applies the new system configuration!
    Probably best to restart first before updating the system build!
    """

    # NOTE; The format script will leave existing disks and partitions that are not defined within
    # the configuration intact.
    # NOTE; The format script will attempt to reapply partition attributes if they do not match
    # with the configuration.
    format_attr_path = (
        f"{FLAKE}#nixosConfigurations.{flake_attr}.config.system.build.formatScript"
    )

    print(f"Checking if format script builds for {flake_attr}..")
    format_script = subprocess.run(
        [
            "nix",
            "build",
            format_attr_path,
            "--no-link",
            "--no-eval-cache",
            "--print-out-paths",
        ],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    print(f"Evaluating machine facts to find {flake_attr}..")
    text_machines = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f"{FLAKE}#host-facts",
            "--apply",
            "builtins.mapAttrs (_: v: v.host-name)",
        ],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    machines = json.loads(text_machines)
    ssh_connection_string = next(
        (
            moniker
            for moniker, host_name in machines.items()
            if flake_attr == host_name or flake_attr == moniker
        ),
        None,
    )

    assert ssh_connection_string, """
        There is no ssh moniker found for the provided host attribute.
        Make sure the desired host returns the expected option host-facts.<moniker>.host-name using the nixos configuration options `proesmans.facts.host-name = "<TODO>";`
    """

    if not ask_user_input(
        f"Update filesystems for {flake_attr} on {ssh_connection_string}?"
    ):
        return

    subprocess.run(
        ["nix", "copy", "--to", f"ssh://{ssh_connection_string}", format_script],
        check=True,
    )

    subprocess.run(["ssh", ssh_connection_string, f"sudo {format_script}"], check=True)

    alert_finish()


@task
# USAGE; invoke dev-rebuild
def dev_rebuild(c: Any) -> None:
    """
    Rebuild the current machine with the host configuration for "development"
    """
    this_hostname = platform.node()
    assert this_hostname == "development", """
        This machine does not have the hostname 'development'. This script will exit to prevent clobbering configuration!
    """
    c.run(f"sudo nixos-rebuild --flake {FLAKE}#development switch")
    alert_finish()


@task
# USAGE; invoke rebuild development
def rebuild(c: Any, flake_attr: str, yes: bool = False) -> None:
    host_attr_path = (
        f"{FLAKE}#nixosConfigurations.{flake_attr}.config.system.build.toplevel"
    )

    if not yes:
        print(f"Checking if host {flake_attr} builds..")
        subprocess.run(
            ["nix-fast-build", "--flake", host_attr_path, "--no-link"], check=True
        )

    print(f"Evaluating machine facts to find {flake_attr}..")
    text_machines = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f"{FLAKE}#host-facts",
            "--apply",
            "builtins.mapAttrs (_: v: v.host-name)",
        ],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    machines = json.loads(text_machines)
    ssh_connection_string = next(
        (
            moniker
            for moniker, host_name in machines.items()
            if flake_attr == host_name or flake_attr == moniker
        ),
        None,
    )

    assert ssh_connection_string, """
        There is no ssh moniker found for the provided hostname.
        Make sure the desired host returns the expected option host-facts.<moniker>.host-name using the nixos configuration options `proesmans.facts.host-name = "<TODO>";`
    """

    if not yes:
        ask = input(
            f"Update configuration {flake_attr} on {ssh_connection_string}? [y/N] "
        )
        if ask != "y":
            return

    subprocess.run(
        [
            "nixos-rebuild",
            "--flake",
            f"{FLAKE}#{flake_attr}",
            "--target-host",
            ssh_connection_string,
            "--use-remote-sudo",
            "switch",
        ],
        check=True,
    )
    alert_finish()


@task
# USAGE; invoke secret-edit development [-f "secrets.encrypted.yaml"]
def secret_edit(c: Any, hostname: str, file: str = "secrets.encrypted.yaml") -> None:
    """
    Load the decryption key from the keyserver, decrypt the development key, start sops to edit the plaintext secrets of the provided file
    """

    host_configuration_dir = FLAKE / "nixosModules" / "hosts" / hostname
    encrypted_file = host_configuration_dir / file

    assert host_configuration_dir.is_dir(), f"""
        There is no configuration folder found for host {hostname}.
        Create a nixos configuration at path `{host_configuration_dir.as_posix()}` first!
    """

    assert encrypted_file.name.endswith("encrypted.yaml"), """
        The convention is to end the filename of encrypted sensitive content with *.encrypted.yaml.
        Update the provided path argument to align with the convention!
    """

    environment = os.environ.copy()
    environment.pop("SOPS_AGE_KEY_FILE", None)
    environment["SOPS_AGE_KEY"] = dev_key_decrypt()

    result = subprocess.run(
        ["sops", encrypted_file.as_posix()],
        env=environment,
        # check=True, # Only verifies exit code 0
    )

    acceptable_sops_exitcodes = [
        0,
        200,  # FileHasNotBeenModified
    ]
    if result.returncode not in acceptable_sops_exitcodes:
        raise subprocess.CalledProcessError(result.returncode, result.args)


@task
# USAGE; invoke ssh-key-create development [-f "secrets.encrypted.yaml"] [-k "ssh_host_ed25519_key"]
def ssh_key_create(
    c: Any,
    hostname: str,
    file: str = "secrets.encrypted.yaml",
    key: str = "ssh_host_ed25519_key",
) -> None:
    """
    Create and encrypt a new SSH private host key.
    """

    host_configuration_dir = FLAKE / "nixosModules" / "hosts" / hostname
    encrypted_file = host_configuration_dir / file

    assert host_configuration_dir.is_dir(), f"""
        There is no configuration folder found for host {hostname}.
        Create a nixos configuration at path `{host_configuration_dir.as_posix()}` first!
    """

    assert encrypted_file.name.endswith("encrypted.yaml"), """
        The convention is to end the filename of encrypted sensitive content with *.encrypted.yaml.
        Update the provided path argument to align with the convention!
    """

    assert key, """
        You must provide a name for the secret value. The value is currently set to an empty string!
        Pass either no argument, or enter a name as argument to this function.
    """

    with TemporaryDirectory() as tmpdir:
        # Prepare filepath and secure file access to store sensitive key material
        tmp = Path(tmpdir)
        tmp.mkdir(parents=True, exist_ok=True)
        tmp.chmod(0o755)
        host_key = tmp / "ssh_host_ed25519_key"
        pub_host_key = host_key.with_suffix(".pub")

        # Create a new key of type 'ed25519', written to the designated filepath
        #
        # ERROR; Explicit program and argument syntax (list/bracket form), because we're not using
        # the shell as intermediate command interpreter
        subprocess.run(
            [
                "ssh-keygen",
                "-t",
                "ed25519",
                "-N",
                "",  # No password
                "-f",
                host_key.as_posix(),
            ],
            check=True,
        )

        with open(host_key, "r", opener=private_opener) as file_handle:
            ssh_private_key = file_handle.read()

        with open(pub_host_key, "r") as file_handle:
            public_key = file_handle.read()

    assert ssh_private_key and public_key, """
        Empty ssh key files were generated, something went unexpectedly wrong!
    """

    # ERROR; File must exist for 'sops set' to work
    if not encrypted_file.is_file():
        subprocess.run(
            [
                "sops",
                "encrypt",
                "--input-type",
                "json",
                "--output-type",
                "yaml",
                "--output",
                encrypted_file.as_posix(),
                # Input file
                "/dev/stdin",
            ],
            input=json.dumps({key: ssh_private_key}),
            text=True,
            check=True,
        )
    else:
        if find_string_in_file(encrypted_file, f"{key}:"):
            warnings.warn(
                "The secret name is found in the encrypted file, it's very likely we're gonna overwrite existing data"
            )
            if not ask_user_input(
                "Do you want to keep going and possibly overwrite your encrypted data?"
            ):
                raise ValueError("Process canceled as to not overwrite data")

        environment = os.environ.copy()
        environment.pop("SOPS_AGE_KEY_FILE", None)
        environment["SOPS_AGE_KEY"] = dev_key_decrypt()

        subprocess.run(
            [
                "sops",
                "set",
                encrypted_file.as_posix(),
                json.dumps([key]),  # Key name selector
                json.dumps(ssh_private_key),  # Value as json string
            ],
            env=environment,
            check=True,
        )

    print(
        f"Private key succesfully encrypted! Below is the corresponding public key\n{public_key}"
    )


@task
def development_key_create(c: Any, name: str = "development") -> None:
    """
    Creates a new development key, password protect it, and store it at path {FLAKE}/<name>.age

    The public part should be provided to SOPS (see '.sops.yaml') for encryption.
    The private part should be made available, in decrypted form, when deploying secrets.
    """
    c.run(f'rage -p -o "{name}.age" <(rage-keygen)')


@task
# USAGE; invoke decrypter-key-create development [-k "development_decrypter"]
def decrypter_key_create(c: Any, hostname: str, key: str = None) -> None:
    """
    Create a new AGE key for encrypting/decrypting all secrets provided to a host.
    """
    host_configuration_dir = FLAKE / "nixosModules" / "hosts" / hostname
    encrypted_file = host_configuration_dir / decryptor_encrypted_filename_default()

    if not host_configuration_dir.is_dir():
        warnings.warn(
            "There is no configuration folder found for the provided hostname"
        )
        if not ask_user_input(
            f"Do you want to create a folder at path {host_configuration_dir.as_posix()}"
        ):
            raise ValueError(f"No configuration folder for host {hostname}")
        host_configuration_dir.mkdir(exist_ok=True)

    age_key = subprocess.run(
        "rage-keygen",
        text=True,  # stdin/stdout are opened in text mode
        check=True,  # Throw exception if command fails
        capture_output=True,  # Redirect stdout/stderr
    ).stdout.strip()

    assert age_key, """
        Unexpected empty output from rage-keygen command!
    """

    # Print everything except last line (presumably private key) to the terminal
    # for the user to further process.
    print("\n".join(age_key.splitlines()[:-1]))

    if not key:
        key = decryptor_name_default(hostname)
        warnings.warn(f"Defaulting to key name {key}")

    # ERROR; File must exist for 'sops set' to work
    if not encrypted_file.is_file():
        subprocess.run(
            [
                "sops",
                "encrypt",
                "--input-type",
                "json",
                "--output-type",
                "yaml",
                # "--filename-override", # Yes, sops has a very weird CLI -_-
                "--output",
                encrypted_file.as_posix(),
                # Input file
                "/dev/stdin",
            ],
            input=json.dumps({key: age_key}),
            text=True,
            check=True,
        )
        return

    if find_string_in_file(encrypted_file, f"{key}:"):
        warnings.warn(
            "The secret name is found in the encrypted file, it's very likely we're gonna overwrite existing data"
        )
        if not ask_user_input(
            "Do you want to keep going and possibly overwrite your encrypted data?"
        ):
            raise ValueError("Process canceled as to not overwrite data")

    environment = os.environ.copy()
    environment.pop("SOPS_AGE_KEY_FILE", None)
    environment["SOPS_AGE_KEY"] = dev_key_decrypt()

    subprocess.run(
        [
            "sops",
            "set",
            encrypted_file.as_posix(),
            json.dumps([key]),  # Key name selector
            json.dumps(age_key),  # Value as json string
        ],
        env=environment,
        check=True,
    )
