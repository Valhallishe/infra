{
  lib,
  options ? { },
}:
let
  inherit (lib) mkOption types;
in
mkOption {
  default = null;
  type = types.nullOr (
    types.submodule {
      options = {
        flows = mkOption {
          default = { };
          type = types.attrsOf (
            types.submodule {
              options = {
                protocol = mkOption {
                  type = types.enum [
                    "http"
                    "https"
                    "tcp"
                    "udp"
                  ];
                  default = "http";
                };
                port = mkOption { type = types.port; };
                proxyProtocol = mkOption {
                  type = types.enum [
                    "none"
                    "v1"
                    "v2"
                    "v2-ssl"
                  ];
                  default = "none";
                };
              };
            }
          );
        };
      }
      // options;
    }
  );
}
