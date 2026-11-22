{ pkgs, brand }:
let
  inherit (pkgs) lib;
  colors = builtins.attrNames brand.dark;
  css = lib.replaceStrings ([ "@brandName@" ] ++ map (key: "#@${key}@") colors) (
    [ (lib.removeSuffix "\"" (lib.removePrefix "\"" (builtins.toJSON brand.name))) ]
    ++ map (key: "#${brand.dark.${key}}") colors
  ) (builtins.readFile ../../../themes/authentik/theme.css);
in
pkgs.runCommand "authentik-branding" { } ''
  mkdir -p "$out/assets"
  cp ${
    pkgs.writeText "branding.json" (builtins.toJSON { inherit (brand) name; })
  } "$out/branding.json"
  cp ${pkgs.writeText "authentik.css" css} "$out/theme.css"
  cp ${brand.wordmark} "$out/assets/logo.svg"
  cp ${brand.symbol} "$out/assets/symbol.svg"
  cp ${brand.background} "$out/assets/background.svg"
  cp ${../../../themes/authentik/apply.py} "$out/apply.py"
  cp ${../../../themes/authentik/restore.py} "$out/restore.py"
''
