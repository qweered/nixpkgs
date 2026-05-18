{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libffcall";
  version = "2.5";

  src = fetchurl {
    url = "mirror://gnu/libffcall/libffcall-${finalAttrs.version}.tar.gz";
    sha256 = "sha256-f0IglrQEmLE4kJOVWCXxQbtn7WAUJJ2IQAlGPceEaHk=";
  };

  enableParallelBuilding = false;

  outputs = [
    "dev"
    "out"
    "doc"
    "man"
  ];

  postInstall = ''
    # Relocate share/html to the conventional share/doc/<name>/html under $out
    # first, then moveToOutput migrates the standard layout into $doc.
    mkdir -p $out/share/doc/libffcall
    mv $out/share/html $out/share/doc/libffcall/html
    moveToOutput share/doc/libffcall "$doc"
    rm -rf $out/share
  '';

  meta = {
    description = "Foreign function call library";
    homepage = "https://www.gnu.org/software/libffcall/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.unix;
  };
})
