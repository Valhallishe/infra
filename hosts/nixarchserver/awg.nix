{ pkgs, decrypt }:
let
  template = ../../peers/archserver/infra0.conf.template;
  prepare = pkgs.writeShellScript "nixarchserver-awg-config" ''
    set -euo pipefail
    umask 077
    private=$(${decrypt ../../secrets/archserver-awg.age})
    public=$(${decrypt ../../secrets/halo-awg-public.age})
    for key in "$private" "$public"; do
      [[ $key =~ ^[A-Za-z0-9+/]{43}=$ ]]
    done
    while IFS= read -r line; do
      line=''${line//@PRIVATE_KEY@/$private}
      printf '%s\n' "''${line//@HALO_PUBLIC_KEY@/$public}"
    done < ${template} > "$1/infra0.conf"
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "nixarchserver-awg.service" ''
    [Unit]
    Description=AmneziaWG infra0 (nixarchserver)
    Wants=network-online.target nss-lookup.target
    After=network-online.target nss-lookup.target awg-quick@infra0.service
    Conflicts=awg-quick@infra0.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-awg
    RuntimeDirectoryMode=0700
    ExecStartPre=${prepare} %t/nixarchserver-awg
    ExecStart=/usr/bin/awg-quick up %t/nixarchserver-awg/infra0.conf
    ExecStop=/usr/bin/awg-quick down %t/nixarchserver-awg/infra0.conf

    [Install]
    WantedBy=multi-user.target
  '';
}
