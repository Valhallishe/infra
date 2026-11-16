{ delib, inputs, config, ... }:
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
    age.secrets.halo-awg.file = ../../secrets/halo-awg.age;
    networking.firewall.allowedUDPPorts = [ 51825 ];
    networking.wireguard.useNetworkd = false;
    networking.wireguard.interfaces.infra0 = {
      type = "amneziawg";
      ips = [ "10.1.0.1/32" ];
      listenPort = 51825;
      privateKeyFile = config.age.secrets.halo-awg.path;
      extraOptions = {
        Jc = 4;
        Jmin = 40;
        Jmax = 70;
        S1 = 37;
        S2 = 73;
        H1 = 52194021;
        H2 = 52194022;
        H3 = 52194023;
        H4 = 52194024;
      };
      peers = [
        {
          name = "archserver";
          publicKey = "b2vqxA4jD3pXjdiN8/NnzSduwfShgOd+pEA3+YRIP1E=";
          allowedIPs = [ "10.1.0.2/32" ];
        }
      ];
    };
    systemd.services.systemd-networkd.restartTriggers = [ ../../secrets/halo-network.age ];
  };
}
