{
  pkgs,
  authentikProfile,
  inbuxaProfile,
  nextcloudProfile,
}:
let
  inherit (pkgs) lib;
  colors = lib.mapAttrs (_: color: "#${color}");
  c = colors inbuxaProfile.dark;
  light = colors inbuxaProfile.light;
  nextcloud = colors nextcloudProfile.dark;
  authentik = import ../services/authentik/branding.nix {
    inherit pkgs;
    brand = authentikProfile;
  };
  symbol = builtins.readFile inbuxaProfile.symbol;
  wordmark = builtins.readFile inbuxaProfile.wordmark;
  mailLogo =
    palette:
    lib.replaceStrings
      [
        "#ffab65"
        "0 0 600 295"
        ''x="203" y="0" width="194" height="192"''
        ''x="300" y="265" text-anchor="middle"''
        ''font-size="47"''
        ''letter-spacing="7"''
      ]
      [
        palette.base0D
        "0 0 420 80"
        ''x="0" y="0" width="80" height="80"''
        ''x="94" y="54"''
        ''font-size="38"''
        ''letter-spacing="3"''
      ]
      wordmark;
  assets =
    pkgs.runCommand "inbuxa-brand"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.imagemagick
        ];
      }
      ''
        mkdir -p "$out"
        cp ${pkgs.writeText "brand-dark.svg" (mailLogo c)} "$out/brand-dark.svg"
        cp ${pkgs.writeText "brand-light.svg" (mailLogo light)} "$out/brand-light.svg"
        rsvg-convert -w 420 -h 80 "$out/brand-dark.svg" -o "$out/logo.png"
        source_symbol=${
          pkgs.writeText "valhallishe-symbol.svg" (lib.replaceStrings [ "#ffab65" ] [ c.base0D ] symbol)
        }
        rsvg-convert -w 64 -h 64 "$source_symbol" -o "$out/favicon-64.png"
        rsvg-convert -w 180 -h 180 "$source_symbol" -o "$out/apple-touch-icon.png"
        rsvg-convert -w 192 -h 192 "$source_symbol" -o "$out/icon-192.png"
        rsvg-convert -w 512 -h 512 "$source_symbol" -o "$out/icon-512.png"
        rsvg-convert -w 320 -h 320 "$source_symbol" -o symbol.png
        magick symbol.png -gravity center -background '${c.base00}' -alpha remove -extent 512x512 "$out/icon-maskable.png"
        magick "$out/favicon-64.png" -define icon:auto-resize=64,32,16 "$out/favicon.ico"
      '';
  mailColors = mode: palette: ''
    color-scheme: ${mode};
    --bg: ${palette.base00};
    --bg-sunken: ${palette.base01};
    --bg-elev: ${palette.base07};
    --bg-hover: ${palette.base01};
    --bg-active: ${palette.base02};
    --fg: ${palette.base05};
    --fg-muted: ${palette.base04};
    --fg-faint: ${palette.base04};
    --border: ${palette.base02};
    --border-strong: ${palette.base03};
    --accent: ${palette.base0D};
    --accent-fg: ${palette.base00};
    --accent-soft: color-mix(in srgb, var(--accent) 16%, var(--bg));
    --accent-soft-fg: ${palette.base0D};
    --link: ${palette.base0D};
    --focus-ring: 0 0 0 3px color-mix(in srgb, var(--accent) 45%, transparent);
    --danger: ${palette.base08};
    --success: ${palette.base0B};
    --warn: ${palette.base0A};
    --danger-soft: color-mix(in srgb, var(--danger) 12%, var(--bg));
    --success-soft: color-mix(in srgb, var(--success) 12%, var(--bg));
    --warn-soft: color-mix(in srgb, var(--warn) 12%, var(--bg));
    --unread-bg: var(--bg-elev);
    --read-bg: var(--bg);
    --selected-bg: var(--accent-soft);
    --star: var(--warn);
    --q1: var(--accent);
    --q2: var(--success);
    --q3: ${palette.base0E};
    --role-inbox: var(--accent);
    --role-drafts: var(--q3);
    --role-sent: var(--success);
    --role-archive: var(--warn);
    --role-junk: var(--warn);
    --role-trash: var(--danger);
    --role-scheduled: var(--accent);
    --scrollbar: color-mix(in srgb, var(--fg) 28%, transparent);
    --raise-sheen: none;
    --raise-sheen-strong: none;
  '';
in
pkgs.linkFarm "service-themes" {
  "inbuxa-brand" = assets;
  inherit authentik;
  "authentik.css" = "${authentik}/theme.css";
  "inbuxa-webmail.conf" = pkgs.replaceVars ../services/inbuxa/webmail-theme.conf.in {
    brandName = lib.replaceStrings [ "\\" "'" "$" ] [ "\\\\" "\\\\u0027" "\\\\u0024" ] (
      builtins.toJSON inbuxaProfile.name
    );
  };
  "inbuxa.css" = pkgs.writeText "inbuxa.css" ''
    :root {
      --valhallishe-logo: url("/_infra/brand-light.svg");
      --valhallishe-preview-light: linear-gradient(135deg, ${light.base00} 55%, ${light.base0D} 55%);
      --valhallishe-preview-dark: linear-gradient(135deg, ${c.base00} 55%, ${c.base0D} 55%);
    }
    :root[data-theme="dark"] { --valhallishe-logo: url("/_infra/brand-dark.svg"); }
    :root:root:root[data-palette="valhallishe"] {
      ${mailColors "light" light}
    }
    :root:root:root[data-palette="valhallishe"][data-theme="dark"] {
      ${mailColors "dark" (c // { base07 = c.base01; })}
    }
    .topbar .brand img,
    .login-card .logo img {
      content: var(--valhallishe-logo);
    }
    .topbar .brand img {
      width: 152px;
      height: 32px;
    }
    .login-card .logo img {
      width: 265px;
      height: auto;
      aspect-ratio: 420 / 80;
    }
    .topbar .brand .brand-name,
    .login-card .logo h1 {
      position: absolute;
      width: 1px;
      height: 1px;
      margin: 0;
      overflow: hidden;
      clip-path: inset(50%);
      white-space: nowrap;
    }
    [data-palette="valhallishe"] {
      .login-page { background: var(--bg); }
      .skeleton { background: var(--bg-hover); animation: none; }
      .push-dot { background: var(--dot); }
      .ev-block.tentative {
        background-image: none;
        outline: 1px dashed currentColor;
        outline-offset: -2px;
      }
      .freebusy .fb-bar.no-data {
        background: var(--bg-sunken);
        border: 1px dashed var(--border-strong);
      }
    }
  '';
  "nextcloud.sh" = pkgs.writeText "nextcloud.sh" ''
    set -eu
    occ() {
      docker exec -u www-data nextcloud-aio-nextcloud php occ "$@"
    }
    occ theming:config primary_color '${nextcloud.base0D}'
    occ theming:config background_color '${nextcloud.base00}'
    occ theming:config background backgroundColor
  '';
}
