_final: previous: {
  outline = previous.outline.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./allow-csp-subdomain.patch
      ./allow-multiplayer-subdomain.patch
      ./allow-websocket-subdomain.patch
    ];
  });
}
