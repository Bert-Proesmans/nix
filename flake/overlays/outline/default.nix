final: previous: {
  outline = previous.outline.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./allow-websocket-subdomain.patch
    ];
  });
}
