{ delib, ... }:
delib.host {
  name = "halo";
  nixos.stylix = {
    enable = true;
    autoEnable = false;
    polarity = "dark";
    base16Scheme = {
      base00 = "0b0907";
      base01 = "17110e";
      base02 = "38271c";
      base03 = "60402b";
      base04 = "c6ad9c";
      base05 = "fff0e4";
      base06 = "ffcab0";
      base07 = "fff8f1";
      base08 = "f1756a";
      base09 = "ffad67";
      base0A = "e8bb67";
      base0B = "9eb875";
      base0C = "80b9ab";
      base0D = "ff8425";
      base0E = "ce9abc";
      base0F = "c66a2b";
    };
  };
}
