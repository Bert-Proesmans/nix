{ flake, documentation, ... }:
{
  _module.args = {
    # NOTE; The exact path is abstracted behind /var/documentation! Systemd's tmpfiles is ensuring the link points to
    # the proper source!
    # SEEALSO; systemd.tmpfiles.rules below
    documentation = "/var/documentation";
    # Path where media assets are stored for documentation purposes
    documentationAssets = "/var/documentation/assets";
  };

  systemd.tmpfiles.rules = [
    "L+ ${documentation} - - - - ${flake.raw_documentation}"
  ];
}
