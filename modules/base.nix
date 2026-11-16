{ delib, ... }:
delib.module {
  name = "infra.base";
  options.infra.base.enable = delib.boolOption true;
  nixos.ifEnabled = {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
      max-jobs = 1;
    };
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
      randomizedDelaySec = "1h";
    };
    zramSwap = {
      enable = true;
      memoryPercent = 25;
    };
    services.journald.extraConfig = ''
      SystemMaxUse=200M
      SystemKeepFree=500M
      MaxRetentionSec=2week
    '';
    documentation = {
      doc.enable = false;
      info.enable = false;
      nixos.enable = false;
    };
  };
}
