{
  lib,
  config,
  ...
}:
let
  infraConfig = config;
  ipv4 = import ./ipv4.nix { inherit lib; };
  inherit (lib) mkOption types;
  routeType = types.submodule {
    options = {
      domain = mkOption {
        type = types.nullOr (types.strMatching "[a-z0-9]([a-z0-9.-]*[a-z0-9])?");
        default = null;
      };
      to = {
        host = mkOption { type = types.str; };
        service = mkOption { type = types.str; };
        flow = mkOption { type = types.str; };
      };
      listen = {
        protocol = mkOption {
          type = types.nullOr (
            types.enum [
              "http"
              "https"
              "tcp"
              "udp"
            ]
          );
          default = null;
        };
        port = mkOption {
          type = types.nullOr types.port;
          default = null;
        };
        tls = mkOption {
          type = types.nullOr (
            types.enum [
              "none"
              "terminate"
              "passthrough"
            ]
          );
          default = null;
        };
        acceptProxyProtocol = mkOption {
          type = types.bool;
          default = false;
        };
      };
    };
  };
  hostType = types.submodule (
    { name, ... }: {
      imports = [
        ../modules/services/authentik.nix
        ../modules/services/comin.nix
        ../modules/services/immich.nix
        ../modules/services/inbuxa.nix
        ../modules/services/inbuxaRelay.nix
        ../modules/services/minecraft.nix
        ../modules/services/nextcloud.nix
        ../modules/services/peertube.nix
        ../modules/services/vaultwarden.nix
      ];
      options = {
        node = mkOption {
          type = types.str;
          default = name;
        };
        branding = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        publicGateway = mkOption { type = types.str; };
        gateway.routes = mkOption {
          type = types.listOf routeType;
          default = [ ];
        };
        services.awg = import ./service-option.nix {
          inherit lib;
          options.peer = mkOption { type = types.str; };
        };
      };
    }
  );
  nodeType = lib.types.submodule (
    { config, name, ... }: {
      options = {
        hostId = lib.mkOption { type = lib.types.ints.positive; };
        ip = lib.mkOption {
          type = lib.types.str;
          default = ipv4.address infraConfig.infra.network.subnet config.hostId;
        };
        awg = {
          publicKey = lib.mkOption {
            type = lib.types.path;
            default = ../secrets + "/${name}-awg-public.age";
          };
          privateKey = lib.mkOption {
            type = lib.types.path;
            default = ../secrets + "/${name}-awg.age";
          };
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      };
    }
  );
in
{
  options.infra = {
    network = {
      subnet = lib.mkOption {
        type = lib.types.str;
        description = "IPv4 CIDR for the infrastructure overlay.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 51825;
      };
      interface = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]{1,15}";
        default = "infra0";
      };
      obfuscation = lib.mkOption {
        type = lib.types.attrsOf lib.types.int;
        default = {
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
      };
    };
    repository = lib.mkOption {
      type = lib.types.str;
      description = "Git repository used for infrastructure deployment.";
    };
    domain = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9]([a-z0-9.-]*[a-z0-9])?";
      description = "Base domain for infrastructure services.";
    };
    nodes = lib.mkOption {
      default = { };
      type = lib.types.attrsOf nodeType;
      description = "Shared infrastructure nodes.";
    };
    hosts = mkOption {
      type = types.attrsOf hostType;
      default = { };
      description = "Host inventory, including deployed services and gateway routes.";
    };
  };
}
