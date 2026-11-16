{
  delib,
  lib,
  pkgs,
  config,
  ...
}:
delib.module {
  name = "infra.security";
  options.infra.security.enable = delib.boolOption true;
  nixos.ifEnabled = {
    networking.firewall.enable = true;
    networking.nftables.enable = true;
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        X11Forwarding = false;
      };
    };
    services.fail2ban.enable = true;
    services.crowdsec = {
      enable = true;
      settings.lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
      settings.general.api.server.enable = true;
      hub.collections = [
        "crowdsecurity/linux"
        "crowdsecurity/sshd"
      ];
      localConfig.acquisitions = [
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
      ];
    };
    services.crowdsec-firewall-bouncer.enable = true;
    # Work around the pinned NixOS module using an unconfigured cscli and
    # migrating CrowdSec's state directory into systemd's private directory.
    systemd.services.crowdsec.environment.CROWDSEC_FEATURE_RE2_DISABLE_GROK_SUPPORT = "true";
    systemd.services.crowdsec.serviceConfig = {
      PrivateUsers = lib.mkForce false;
      TimeoutStartSec = "10min";
    };
    systemd.services.crowdsec-firewall-bouncer-register = {
      requires = [ "crowdsec.service" ];
      environment.CROWDSEC_FEATURE_RE2_DISABLE_GROK_SUPPORT = "true";
      script = lib.mkForce (
        let
          cscli = "${lib.getExe' pkgs.crowdsec "cscli"} -c ${
            ((pkgs.formats.yaml { }).generate "crowdsec-bouncer-cli.yaml"
              config.services.crowdsec.settings.general
            )
          }";
        in
        ''
          if ${cscli} bouncers list -o json | ${lib.getExe pkgs.jq} -e 'any(.[]; .name == "crowdsec-firewall-bouncer")' >/dev/null; then
            test -s /var/lib/crowdsec-firewall-bouncer-register/api-key.cred
          else
            ${cscli} bouncers add crowdsec-firewall-bouncer -o raw > /var/lib/crowdsec-firewall-bouncer-register/api-key.cred
          fi
        ''
      );
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
      };
    };
  };
}
