{ lib, ... }:
let
  inherit (lib) mkOption types;
  palette = types.attrsOf (types.strMatching "[0-9a-fA-F]{6}");
in
{
  options.infra.branding = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          name = mkOption { type = types.str; };
          wordmark = mkOption { type = types.path; };
          symbol = mkOption { type = types.path; };
          background = mkOption { type = types.path; };
          dark = mkOption { type = palette; };
          light = mkOption { type = palette; };
        };
      }
    );
  };
  config.infra.branding.valhallishe = {
    name = "Valhallishe";
    wordmark = ./assets/valhallishe-logo.svg;
    symbol = ./assets/valhallishe-symbol.svg;
    background = ./assets/background.svg;
    dark = {
      base00 = "141414";
      base01 = "202020";
      base02 = "303030";
      base03 = "808080";
      base04 = "cccccc";
      base05 = "f5f5f5";
      base06 = "ffffff";
      base07 = "ffffff";
      base08 = "ff9999";
      base09 = "ffd09a";
      base0A = "f0d080";
      base0B = "a8db9a";
      base0C = "9adbd4";
      base0D = "ffab65";
      base0E = "dfb8eb";
      base0F = "dca88a";
    };
    light = {
      base00 = "faf7f3";
      base01 = "f0eae3";
      base02 = "e4dbd0";
      base03 = "9b8e81";
      base04 = "645951";
      base05 = "292420";
      base07 = "ffffff";
      base08 = "a32e35";
      base0A = "845b16";
      base0B = "335e30";
      base0D = "9a450b";
      base0E = "744881";
    };
  };
}
