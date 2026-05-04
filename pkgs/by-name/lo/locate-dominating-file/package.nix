{
  fetchFromGitHub,
  lib,
  writeResolvedShellApplication,
  coreutils,
  getopt,
}:

writeResolvedShellApplication {
  pname = "locate-dominating-file";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "roman";
    repo = "locate-dominating-file";
    rev = "v0.0.1";
    hash = "sha256-gwh6fAw7BV7VFIkQN02QIhK47uxpYheMk64UeLyp2IY=";
  };

  installScripts."src/locate-dominating-file.sh" = "bin/locate-dominating-file";

  buildInputs = [
    coreutils
    getopt
  ];

  meta = {
    homepage = "https://github.com/roman/locate-dominating-file";
    description = "Program that looks up in a directory hierarchy for a given filename";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.roman ];
    platforms = lib.platforms.all;
    mainProgram = "locate-dominating-file";
  };
}
