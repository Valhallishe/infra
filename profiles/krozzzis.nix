{
  delib,
  pkgs,
  lib,
  ...
}:
let
  starshipConfig = (pkgs.formats.toml { }).generate "krozzzis-starship.toml" (
    import ./starship.nix { inherit lib; }
  );
in
delib.module {
  name = "infra.krozzzis";
  options.infra.krozzzis.enable = delib.boolOption false;
  nixos.ifEnabled = {
    users.mutableUsers = false;
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        if test "$USER" = krozzzis
          set -gx STARSHIP_CONFIG ${starshipConfig}
          ${lib.getExe pkgs.starship} init fish | source
        end
      '';
    };
    users.users.krozzzis = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.fish;
      packages = [
        pkgs.vim
        pkgs.starship
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3JM/W76cJjAW/1QflJsfrFrL9UuVR5UGmnyhjbIycY"
      ];
    };
    # The account has no password; key-based SSH is the authentication step.
    security.sudo.wheelNeedsPassword = false;
  };
}
