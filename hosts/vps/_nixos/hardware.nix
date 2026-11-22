{
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
  networking.useDHCP = true;
  services.qemuGuest.enable = true;
}
