{ delib, inputs, ... }:
delib.host {
  name = "halo";
  useHomeManagerModule = false;
  myconfig.infra.krozzzis.enable = true;
  myconfig.infra.web.enable = true;
  nixos = {
    imports = [
      inputs.disko.nixosModules.disko
      inputs.comin.nixosModules.comin
      inputs.agenix.nixosModules.default
      ../../domains/valhallishe.net.nix
    ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    networking.hostName = "halo";
    services.comin = {
      enable = true;
      remotes = [
        {
          name = "origin";
          url = "https://github.com/Valhallishe/infra.git";
          branches.main.name = "main";
        }
      ];
    };

    boot.loader.grub = {
      enable = true;
      configurationLimit = 5;
    };
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "ahci"
      "sd_mod"
    ];
    boot.kernelParams = [
      "console=tty1"
      "console=ttyS0"
    ];
    services.qemuGuest.enable = true;
    # zram has higher priority; this file provides a disk-backed fallback.
    swapDevices = [
      {
        device = "/swapfile";
        size = 2048;
        priority = 1;
      }
    ];

    networking.useDHCP = false;
    networking.useNetworkd = true;
    services.resolved.enable = true;
    age.secrets.halo-network = {
      file = ../../secrets/halo-network.age;
      path = "/run/systemd/network/10-wan.network";
      mode = "0644";
    };
    systemd.services.systemd-networkd.restartTriggers = [ ../../secrets/halo-network.age ];
  };
}
