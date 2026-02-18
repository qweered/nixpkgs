{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  protobuf,
  alsa-lib,
  at-spi2-core,
  dbus,
  ffmpeg,
  libxcb,
  oniguruma,
  onnxruntime,
  openssl,
  sqlite,
  stdenv,
  tesseract,
  libx11,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxtst,
}:
rustPlatform.buildRustPackage rec {
  pname = "screenpipe";
  version = "0.3.135";

  src = fetchFromGitHub {
    owner = "screenpipe";
    repo = "screenpipe";
    tag = "v${version}";
    hash = "sha256-Wom62zlx9HRoqt6uUbGfCl+Y8aKm1cG1tBTDDDf8BqY=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "accessibility-0.2.0" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "candle-core-0.8.3" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "cidre-0.14.0" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "cpal-0.15.3" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "ffmpeg-sidecar-2.0.5" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "hf-hub-0.3.2" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "knf-rs-0.2.4" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "rusty-tesseract-1.1.10" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "sck-rs-0.1.0" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "vad-rs-0.2.0" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      "whisper-rs-0.15.1" = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    protobuf
    rustPlatform.bindgenHook
  ];

  buildInputs =
    [
      ffmpeg
      oniguruma
      onnxruntime
      openssl
      sqlite
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      alsa-lib
      at-spi2-core
      dbus
      libxcb
      tesseract
      libx11
      libxext
      libxfixes
      libxi
      libxrandr
      libxtst
    ];

  cargoBuildFlags = [
    "-p"
    "screenpipe-server"
  ];

  env = {
    RUSTONIG_SYSTEM_LIBONIG = true;
    ORT_STRATEGY = "system";
    ORT_LIB_LOCATION = "${onnxruntime}/lib";
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    NIX_CFLAGS_COMPILE = "-Wno-error=implicit-function-declaration";
    NIX_CXXFLAGS_COMPILE = "-fpermissive";
  };

  RUSTFLAGS = lib.optionalString stdenv.hostPlatform.isLinux "-C link-arg=-Wl,--allow-multiple-definition";

  doCheck = false;

  meta = {
    description = "24/7 screen and audio capture with AI-powered search";
    homepage = "https://github.com/screenpipe/screenpipe";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ dit7ya ];
    mainProgram = "screenpipe";
    platforms = lib.platforms.linux;
  };
}
