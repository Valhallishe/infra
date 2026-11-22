{
  config,
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
{
  options.infra.serviceThemes = lib.mkOption {
    type = lib.types.package;
    description = "Themes for the Docker services on Archserver.";
  };

  config = lib.optionalAttrs (options ? stylix) (
    lib.mkIf config.stylix.enable (
      let
        c = config.lib.stylix.colors.withHashtag;
        names = builtins.attrNames (
          lib.filterAttrs (name: _: builtins.match "base[0-9A-F]{2}" name != null) c
        );
        render = lib.replaceStrings (map (name: "#@${name}@") names) (map (name: c.${name}) names);
      in
      {
        infra.serviceThemes = pkgs.linkFarm "service-themes" {
          "authentik.css" = pkgs.writeText "authentik.css" (
            render (builtins.readFile (inputs.self + "/themes/authentik/theme.css"))
          );
          "inbuxa.css" = pkgs.writeText "inbuxa.css" ''
            :root:root:root {
              color-scheme: dark;
              --bg: ${c.base00};
              --bg-sunken: ${c.base00};
              --bg-elev: ${c.base01};
              --bg-hover: ${c.base02};
              --bg-active: ${c.base03};
              --fg: ${c.base05};
              --fg-muted: ${c.base04};
              --fg-faint: ${c.base04};
              --border: ${c.base02};
              --border-strong: ${c.base03};
              --accent: ${c.base0D};
              --accent-fg: ${c.base00};
              --accent-soft: ${c.base02};
              --accent-soft-fg: ${c.base09};
              --link: ${c.base09};
              --focus-ring: ${c.base0D};
              --danger: ${c.base08};
              --success: ${c.base0B};
              --warn: ${c.base0A};
            }
          '';
          "nextcloud.sh" = pkgs.writeText "nextcloud.sh" ''
            set -eu
            occ() {
              docker exec -u www-data nextcloud-aio-nextcloud php occ "$@"
            }
            occ theming:config primary_color '${c.base0D}'
            occ theming:config background_color '${c.base00}'
          '';
        };
      }
    )
  );
}
