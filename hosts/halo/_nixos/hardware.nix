{
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
}
