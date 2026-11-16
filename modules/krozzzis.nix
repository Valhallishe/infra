{
  delib,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
delib.module {
  name = "infra.krozzzis";
  nixos.ifEnabled =
    let
      starshipConfig = (pkgs.formats.toml { }).generate "krozzzis-starship.toml" (
        import (inputs.self + "/lib/starship.nix") { inherit lib; }
      );
    in
    {
      age.secrets.admin-ssh = {
        file = (inputs.self + "/secrets/admin-ssh.age");
        mode = "0444";
      };
      services.openssh.extraConfig = ''
        Match User krozzzis
          AuthorizedKeysFile ${config.age.secrets.admin-ssh.path}
        Match all
      '';
      # SSH authentication is configured via a runtime agenix file.
      users.allowNoPasswordLogin = true;
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
      };
      # The account has no password; key-based SSH is the authentication step.
      security.sudo.wheelNeedsPassword = false;
    };
}
