{
  bc,
  coreutils,
  fetchFromGitHub,
  ffmpeg,
  findutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  lame,
  lib,
  mediainfo,
  mp4v2,
  ncurses,
  writeResolvedShellApplication,
}:

writeResolvedShellApplication {
  pname = "aaxtomp3";
  version = "1.3";

  src = fetchFromGitHub {
    owner = "krumpetpirate";
    repo = "aaxtomp3";
    tag = "v1.3";
    hash = "sha256-7a9ZVvobWH/gPxa3cFiPL+vlu8h1Dxtcq0trm3HzlQg=";
  };

  # Rename the script names lowercase and bake the interactive
  # driver's self-call to the absolute store path. (resholve's
  # `fix.$AAXTOMP3` text-replaced `$AAXTOMP3` everywhere including
  # inside `call="$AAXTOMP3"`; rusholve's `--map` only fires at
  # command position, so we substitute the path here directly.)
  postPatch = ''
    substituteInPlace AAXtoMP3 \
      --replace-fail 'AAXtoMP3' 'aaxtomp3'
    substituteInPlace interactiveAAXtoMP3 \
      --replace-fail 'AAXtoMP3' 'aaxtomp3' \
      --replace-fail 'call="./aaxtomp3"' 'call="${placeholder "out"}/bin/aaxtomp3"'
  '';

  installScripts = {
    "AAXtoMP3" = "bin/aaxtomp3";
    "interactiveAAXtoMP3" = "bin/interactiveaaxtomp3";
  };

  buildInputs = [
    bc
    coreutils
    ffmpeg
    findutils
    gawk
    gnugrep
    gnused
    jq
    lame
    mediainfo
    mp4v2
    ncurses
  ];

  # Auto mode handles dynamic command words via `--skip` / `--map`.
  # `$call` is the interactive driver's progressively-built command
  # line — its prefix is the absolute path baked in by `postPatch`,
  # so accept it unchanged at command position. `$FIND` / `$GREP` /
  # `$SED` are bare-name maps that route through `buildInputs`
  # (rusholve resolves the bare name through `--inputs` exactly the
  # way a static reference would).
  #
  # `--allow-known-gaps` accepts the debug helper's
  #   eval val="\$${args[$n]}"
  # idiom: indirect variable lookup via eval. The variable name is
  # static-but-unknown to the resolver; the script is audited.
  rusholveFlags = [
    "--allow-known-gaps"
    "--skip"
    "$call"
    "--map"
    "$FIND=find"
    "--map"
    "$GREP=grep"
    "--map"
    "$SED=sed"
  ];

  meta = {
    description = "Convert Audible's .aax filetype to MP3, FLAC, M4A, or OPUS";
    homepage = "https://krumpetpirate.github.io/AAXtoMP3";
    license = lib.licenses.wtfpl;
    mainProgram = "aaxtomp3";
    maintainers = [ ];
  };
}
