{ lib, config, inputs, ... }:
let
  infraConfig = config;
  ipv4 = import (inputs.self + "/lib/ipv4.nix") { inherit lib; };
  nodeType = lib.types.submodule ({ config, name, ... }: {
    options = {
      hostId = lib.mkOption { type = lib.types.ints.positive; };
      ip = lib.mkOption {
        type = lib.types.str;
        default = ipv4.address infraConfig.infra.network.subnet config.hostId;
      };
      awg = {
        publicKey = lib.mkOption {
          type = lib.types.path;
          default = inputs.self + "/secrets/${name}-awg-public.age";
        };
        privateKey = lib.mkOption {
          type = lib.types.path;
          default = inputs.self + "/secrets/${name}-awg.age";
        };
        endpoint = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      };
    };
  });
in
{
  options.infra = {
    domain = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9]([a-z0-9.-]*[a-z0-9])?";
      description = "Base domain for infrastructure services.";
    };
    nodes = lib.mkOption {
      default = { };
      type = lib.types.attrsOf nodeType;
      description = "Shared infrastructure nodes.";
    };
    services = lib.mkOption {
      default = { };
      description = "Published services; declaring a service does not deploy it.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          routes = lib.mkOption {
            default = [ ];
            description = "Published HTTP(S) endpoints of this service.";
            type = lib.types.listOf (lib.types.submodule ({ config, ... }: {
              options = {
                domain = lib.mkOption {
                  type = lib.types.nullOr (lib.types.strMatching "[a-z0-9]([a-z0-9.-]*[a-z0-9])?");
                  default = null;
                };
                protocol = lib.mkOption {
                  type = lib.types.enum [ "http" "https" "tcp" ];
                  default = "https";
                  description = "Incoming protocol; HTTPS enables automatic TLS.";
                };
                tls = lib.mkOption {
                  type = lib.types.enum [ "none" "terminate" "passthrough" ];
                  default = if config.protocol == "https" then "terminate" else "none";
                };
                proxy_protocol = {
                  accept = lib.mkOption { type = lib.types.bool; default = false; };
                  send = lib.mkOption {
                    type = lib.types.enum [ "none" "v1" "v2" "v2-ssl" ];
                    default = "none";
                  };
                };
                in_port = lib.mkOption { type = lib.types.port; default = 443; };
                in_node = lib.mkOption { type = nodeType; };
                out_port = lib.mkOption { type = lib.types.port; };
                out_node = lib.mkOption { type = nodeType; };
                out_protocol = lib.mkOption {
                  type = lib.types.enum [ "http" "https" ];
                  default = "http";
                  description = "Protocol used to reach the backend.";
                };
              };
            }));
          };
        };
      });
    };
    web = {
      enable = lib.mkEnableOption "public web hosting";
      node = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "Node whose incoming routes this proxy serves.";
      };
    };
  };
}
