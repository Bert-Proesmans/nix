{
  fetchFromGitHub,
  python3Packages,
}:
let
  pname = "email-oauth2-proxy";
  version = "2025-06-25";
in
python3Packages.buildPythonApplication {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "simonrob";
    repo = pname;
    tag = version;
    hash = "sha256-0/Ln3CJ50HrABZAyZPYEr2dUiAs44Nua4Q/OO8TnPvo=";
  };

  pyproject = true;

  build-system = [ python3Packages.setuptools ];

  dependencies = [
    python3Packages.cryptography
    python3Packages.prompt-toolkit
    python3Packages.pyasyncore
    python3Packages.pyjwt
  ];

  meta = {
    description = ''
      An IMAP/POP/SMTP proxy that transparently adds OAuth 2.0 authentication
      for email clients that don't support this method
    '';
    homepage = "https://github.com/simonrob/email-oauth2-proxy";
    mainProgram = "emailproxy";
  };
}
