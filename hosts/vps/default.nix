{ delib, inputs, ... }:
delib.host {
  name = "vps";
  useHomeManagerModule = false;
  nixos = {
    imports = [ inputs.disko.nixosModules.disko ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";

    boot.loader.systemd-boot = {
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
    networking.hostName = "vps";
    networking.useDHCP = true;
    services.qemuGuest.enable = true;

  };
}
