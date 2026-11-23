{ lib, ... }:
{
  options.services.opencloud = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      apps = {
        model3d = lib.mkEnableOption "3D model viewer";
        unzip = lib.mkEnableOption "ZIP extraction";
        epubReader = lib.mkEnableOption "EPUB reader";
        pdfViewer = lib.mkEnableOption "PDF viewer";
      };
      branding = lib.mkOption { type = lib.types.str; };
    };
  };
}
