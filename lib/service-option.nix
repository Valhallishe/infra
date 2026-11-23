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
        storage = mkOption {
          default = { };
          description = "Named persistent storage areas for the service.";
          type = types.attrsOf (
            types.submodule (
              { config, ... }: {
                options = {
                  kind = mkOption {
                    type = types.enum [
                      "path"
                      "dockerVolume"
                      "external"
                    ];
                    default = "path";
                  };
                  location = mkOption {
                    type =
                      {
                        path = types.strMatching "/.*";
                        dockerVolume = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_.-]*";
                        external = types.nullOr types.str;
                      }
                      .${config.kind};
                    default = null;
                    description = "Absolute host path, Docker volume name, or external storage reference.";
                  };
                  backup = mkOption {
                    type = types.enum [
                      "inherit"
                      "include"
                      "exclude"
                    ];
                    default = "inherit";
                    description = "Backup intent for this area. A nested path can override its parent.";
                  };
                  mount = mkOption {
                    type = types.nullOr (
                      types.submodule {
                        options = {
                          path = mkOption { type = types.strMatching "/.*"; };
                          unit = mkOption { type = types.str; };
                          uuid = mkOption { type = types.str; };
                        };
                      }
                    );
                    default = null;
                    description = "Optional filesystem identity and mount dependency for a host path.";
                  };
                };
              }
            )
          );
        };
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
