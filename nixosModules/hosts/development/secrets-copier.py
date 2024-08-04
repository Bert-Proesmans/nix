# ERROR; For some reason flake8 requires 80 characters width for all lines
# including contents!

# During nix build this file is run through the PEP-validator, and stuff like
# "line-too-long" will cause build failure.
import warnings
from pathlib import Path
import sys

QEMU_FWCFG_PATH = Path("/sys/firmware/qemu_fw_cfg/by_name/opt/secret-seeder")


def copy_secret(tag: str, path: str):
    # WARN; The tags are symlinks we want to explicitly resolve
    source = QEMU_FWCFG_PATH / tag
    assert source.exists(), f"""
        The provided tag {tag} does not exist in the firmware configuration \
        table! Pass this secret into the virtual machine using arguments \
        '-fw_cfg name=opt/secret-seeder/{tag},file=<contents>'.
    """

    source = source.resolve(strict=True)

    with open(source / "size", "rt") as file_handle:
        # SAFETY; Safe to open in text mode because remaining file page is
        # filled with zeroes (0)
        # SAFETY; Maximum length restricted to integer domain
        # SAFETY; Should throw on errors
        size = int(file_handle.read().strip())

    target = Path(path)
    # TODO; Handle parent directory access control
    target.parent.mkdir(parents=True, exist_ok=True)

    assert not target.is_dir(), """
        Target path is a directory, not recovering from this situation!
    """

    if target.exists():
        warnings.warning("""
            The target path already exists. \
            Trying to remove the target before continuing.
        """)
        target.unlink(missing_ok=True)

    assert not target.exists() or not target.is_file(), """
        Couldn't remove the target and it's something else than a file. \
        Cannot proceed!
    """

    # TODO; Handle file access control
    with (
        open(source / "raw", "rb") as source_handle,
        open(target, "wb") as target_handle,
    ):
        # NOTE; Target file is automatically truncated
        target_handle.write(source_handle.read(size))


def main():
    # Check if the correct number of arguments are provided
    if len(sys.argv) != 3:
        print("Usage: script.py <secret-tag> <target-path>")
        sys.exit(1)

    assert QEMU_FWCFG_PATH.is_dir(), """
        There is no QEMU data mounted into the filesystem! Make sure \
        this host is a QEMU virtual machine.
        Pass firmware configuration into the virtual machine using \
        arguments '-fw_cfg name=opt/secret-seeder/<tag>,file=<file-to-insert>'
    """
    tag = sys.argv[1]
    path = sys.argv[2]
    copy_secret(tag, path)


if __name__ == "__main__":
    main()
