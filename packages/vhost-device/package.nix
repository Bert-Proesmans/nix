{ lib
, fetchFromGitHub
, installShellFiles
, rustPlatform
, protobuf
, stdenv
}:

rustPlatform.buildRustPackage rec {
  pname = "vhost-device";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "rust-vmm";
    repo = "vhost-device";
    rev = "vhost-device-vsock-v${version}";
    hash = "sha256-78ApeHdPSLA46JP9xg6LUvTTpJmpn5LjdcsrZmX9Lgk=";
  };

  cargoHash = "sha256-2KqkKuGTB13XmZOmpZzSKIGeBPn0en56h/Y3S7PJxOA=";

  buildAndTestSubdir = "vhost-device-vsock";

  nativeBuildInputs = [ ];

  # uses currently unstable tokio features
  # RUSTFLAGS = "--cfg tokio_unstable";

  # checkFlags = [
  #   # tests depend upon git repository at test execution time
  #   "--skip bootstrap"
  #   "--skip config::tests::args_example_changed"
  #   "--skip config::tests::toml_example_changed"
  # ];

  meta = with lib; {
    description = "A vhost-device-vsock device daemon that enables communication between an application running in the guest i.e inside a VM and an application running on the host i.e outside the VM.";
    longDescription = null;
    changelog = "https://github.com/rust-vmm/vhost-device/releases/tag/vhost-device-vsock-v${version}";
    homepage = "https://github.com/rust-vmm/vhost-device";
    mainProgram = "vhost-device-vsock";
    license = with licenses; [ asl20 bsd3 ];
    maintainers = [ ];
  };
}
