{
  lib,
  config,
  inputs,
  ...
}:
let
  infraConfig = config;
  ipv4 = import (inputs.self + "/lib/ipv4.nix") { inherit lib; };
  namedFlows =
    options:
    lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }: {
            options = options config;
          }
        )
      );
    };
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
            default = inputs.self + "/secrets/${name}-awg-public.age";
          };
          privateKey = lib.mkOption {
            type = lib.types.path;
            default = inputs.self + "/secrets/${name}-awg.age";
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
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            inbound = namedFlows (config: {
              protocol = lib.mkOption {
                type = lib.types.enum [
                  "http"
                  "https"
                  "tcp"
                  "udp"
                ];
                default = "https";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 443;
              };
              tls = lib.mkOption {
                type = lib.types.enum [
                  "none"
                  "terminate"
                  "passthrough"
                ];
                default = if config.protocol == "https" then "terminate" else "none";
              };
              acceptProxyProtocol = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            });
            outbound = namedFlows (_: {
              node = lib.mkOption { type = lib.types.str; };
              port = lib.mkOption { type = lib.types.port; };
              protocol = lib.mkOption {
                type = lib.types.enum [
                  "http"
                  "https"
                ];
                default = "http";
              };
              proxyProtocol = lib.mkOption {
                type = lib.types.enum [
                  "none"
                  "v1"
                  "v2"
                  "v2-ssl"
                ];
                default = "none";
              };
            });
          };
        }
      );
    };
    web = {
      enable = lib.mkEnableOption "public web hosting";
      routes = lib.mkOption {
        default = [ ];
        description = "Routes published by this gateway.";
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              service = lib.mkOption { type = lib.types.str; };
              inbound = lib.mkOption { type = lib.types.str; };
              outbound = lib.mkOption { type = lib.types.str; };
              domain = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "[a-z0-9]([a-z0-9.-]*[a-z0-9])?");
                default = null;
              };
            };
          }
        );
      };
      node = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "Node whose incoming routes this proxy serves.";
      };
    };
  };
}
